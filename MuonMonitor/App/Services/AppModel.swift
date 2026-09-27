import Foundation
import SwiftData
import Observation
import CoreLocation
import UIKit

/// Detector settings returned by the `status` command.
struct DetectorStatus: Equatable {
    var label = ""
    var logFile = ""
    var envFile = ""
    var clockSet = false
    var wifiKeepOn = false
    var dac: [Int] = []
    var raw: [String: String] = [:]

    init() {}
    init(_ d: [String: Any]) {
        label = d["label"] as? String ?? ""
        logFile = d["log"] as? String ?? ""
        envFile = d["env"] as? String ?? ""
        clockSet = (d["time_set"] as? Bool) ?? ((d["epoch"] as? Double ?? 0) > 1.6e9)
        wifiKeepOn = d["keep_wifi"] as? Bool ?? d["wifi_keep"] as? Bool ?? false
        dac = d["dac"] as? [Int] ?? []
        raw = d.reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
    }
}

/// App state: owns the detector link, the active run and everything that
/// follows from each completed minute (storage, events, alerts, Live Activity,
/// widgets and the cosmic folder). Counts are stored raw — no corrections.
@Observable
@MainActor
final class AppModel {
    let link: DetectorLink
    let location = LocationTracker()
    let cloud = CloudFolder()
    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored private let live = LiveActivityController()
    var context: ModelContext { container.mainContext }

    private(set) var logging: Bool
    var currentRun: Run?
    private(set) var latest: Telemetry?
    var lastSeen: Date?
    var lastMinuteEnd: Date?
    var recent: [MinuteRecord] = []        // last 4 h of this session, for the Now screen
    var phase: Phase = .stopped
    private(set) var status = DetectorStatus()
    var issue: String?
    private(set) var syncing = false
    private var needsGapSync = false
    private var nextSyncAttempt = Date.distantPast
    private var syncTask: Task<Void, Never>?
    var firmwareIdentity: [String: String] = [:]
    private var capabilityBoot: String?
    private var recoverySchema = 0
    private var nextTransport = Date.distantPast
    private var nextLocationRead = Date.distantPast
    private var nextJournalScan = Date.distantPast
    private var journalEnds: [String: Int] = [:]
    private var journalHeaders: [String: String] = [:]
    private var deferredRecords: [String: Date] = [:]
    private var deferredLocations: [String: Date] = [:]
    var expertMode: Bool { didSet { UserDefaults.standard.set(expertMode, forKey: "expertMode") } }
    let demo: Bool

    @ObservationIgnored private var previous: Telemetry?
    @ObservationIgnored private var seen = Set<String>()
    @ObservationIgnored private var lastExport = Date.distantPast
    @ObservationIgnored private var lastHealthCheck = Date.distantPast
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var lastWidget: WidgetSnapshot?
    @ObservationIgnored private var lastWidgetReload = Date.distantPast

    init(container: ModelContainer, demo: Bool = false) {
        self.container = container
        self.demo = demo
        self.link = DetectorLink(restoring: !demo)
        expertMode = UserDefaults.standard.bool(forKey: "expertMode")
        logging = demo ? true : UserDefaults.standard.bool(forKey: "logging")
        link.onDiagnostic = { [weak self] message in MainActor.assumeIsolated { self?.addEvent(.note, message, at: Date()) } }
        link.onSample = { [weak self] t in MainActor.assumeIsolated { self?.ingest(t) } }
        link.onDisconnect = { [weak self] in MainActor.assumeIsolated { self?.refreshPhase() } }
        IntentActions.setLogging = { [weak self] on in
            guard let self else { return }
            if on { self.start() } else { self.stop() }
        }
        IntentActions.startPhysicsRun = { [weak self] in
            guard let self else { return }
            try await self.startPhysicsRun()
        }
        if demo { loadDemo(); return }
        if logging { resume() } else { publishWidget() }
        ticker = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPhase() }
        }
    }

    // MARK: logging

    var needsPairing: Bool { link.knownDetector == nil && !demo }

    func start() {
        guard !logging, !demo else { return }
        let run = Run(name: Self.defaultName(Date()), start: Date())
        run.isLive = true
        context.insert(run); try? context.save()
        currentRun = run; seen = []; previous = nil; recent = []
        needsGapSync = false; nextSyncAttempt = .distantPast
        logging = true; UserDefaults.standard.set(true, forKey: "logging")
        Alerts.requestPermission()
        if let run = currentRun { location.start(runID: run.id) }; link.connect()
        phase = .searching
        do { try live.start(activityState()) } catch { issue = "Live Activity could not start: \(error.localizedDescription)" }
        publishWidget()
    }

    func stop() {
        guard logging, !demo else { return }
        logging = false; UserDefaults.standard.set(false, forKey: "logging")
        syncTask?.cancel(); needsGapSync = false
        link.disconnect(); location.stop(); live.end(); Alerts.cancelOverdue()
        if let run = currentRun {
            run.isLive = false
            run.end = lastMinuteEnd ?? Date()
            if run.minutes.isEmpty { context.delete(run) } else { cloud.save(run) }
            try? context.save()
        }
        currentRun = nil; phase = .stopped
        publishWidget()
    }

    private func resume() {
        let d = FetchDescriptor<Run>(predicate: #Predicate { $0.isLive == true }, sortBy: [SortDescriptor(\.start, order: .reverse)])
        currentRun = try? context.fetch(d).first
        if currentRun == nil { let r = Run(name: Self.defaultName(Date()), start: Date()); r.isLive = true; context.insert(r); currentRun = r }
        if let run = currentRun {
            let mins = run.sortedMinutes
            seen = Set(mins.map { "\($0.bootID)-\($0.sequence)" })
            recent = Array(mins.suffix(240)).map(\.record)
            lastMinuteEnd = recent.last?.date
            needsGapSync = RunRecovery.hasGap(mins.map(\.record))
        }
        if let run = currentRun { location.start(runID: run.id) }; link.connect(); phase = .connecting
        try? live.start(activityState())
    }

    func restartLiveActivity() {
        do { try live.restart(activityState()) } catch { issue = "Live Activity could not start: \(error.localizedDescription)" }
    }

    static func defaultName(_ d: Date) -> String { "Run " + d.formatted(.dateTime.month(.abbreviated).day().hour().minute()) }
    static func isDefaultName(_ n: String) -> Bool { n.hasPrefix("Run ") }

    // MARK: each telemetry read

    private func ingest(_ t: Telemetry) {
        lastSeen = Date(); latest = t
        detectStateEvents(t)
        if t.hasSample, logging || demo {
            let key = "\(t.bootID)-\(t.sequence)"
            if !seen.contains(key) {
                seen.insert(key)
                record(t)
            }
        }
        previous = t
        refreshPhase()

        syncGapsIfNeeded()
    }

    private func record(_ t: Telemetry) {
        guard let run = currentRun else { return }
        let clockSet = t.flags & 8 != 0
        let end = clockSet ? Date(timeIntervalSince1970: TimeInterval(t.epoch)) : Date().addingTimeInterval(-t.sampleAge)
        // An imported older-format SD row may not carry the BLE boot/sequence key.
        if run.minutes.contains(where: { $0.fromSD && ($0.bootID.isEmpty
            ? abs($0.epoch - end.timeIntervalSince1970) < 20
            : $0.bootID == String(t.bootID) && $0.sequence == Int(t.sequence)) }) { return }
        let fix = location.fix(for: end)
        var rec = MinuteRecord(epoch: end.timeIntervalSince1970, sequence: Int(t.sequence), bootID: String(t.bootID),
                               intervalMS: Int(t.interval), physics: t.physics, counts: t.counts.map(Int.init),
                               temperature: t.temperature, pressure: t.pressure,
                               latitude: fix?.coordinate.latitude, longitude: fix?.coordinate.longitude,
                               altitude: fix.flatMap { $0.verticalAccuracy >= 0 ? $0.altitude : nil },
                               horizontalAccuracy: fix?.horizontalAccuracy, fromSD: false)
        rec.diagnostics = ["transport": "BLE", "acquisition": "live", "sd_recovered": "0",
            "detector_epoch": String(t.epoch), "time_set": clockSet ? "1" : "0",
            "utc_estimated": clockSet ? "0" : "1", "uptime_ms": String(t.sampleUptime),
            "device_id": RecordIntegrity.deviceKey(t.deviceID), "physics_exposure_ms": String(t.exposure)]
        for (i, total) in t.totals.enumerated() { rec.diagnostics?["physics_total\(i)"] = String(total) }
        if let fix {
            rec.diagnostics?["location_source"] = "gps"
            rec.diagnostics?["location_revision"] = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            rec.diagnostics?["fix_epoch_ms"] = String(Int64(fix.timestamp.timeIntervalSince1970 * 1000))
        }
        for assignment in run.stationaryLocations { assignment.apply(to: &rec) }
        if let last = recent.last, RunRecovery.hasGap([last, rec]) { needsGapSync = true }
        // Missed minutes on the same boot: note the gap; the SD card has them.
        if let last = recent.last, last.bootID == rec.bootID, rec.sequence > last.sequence + 1 {
            let missed = rec.sequence - last.sequence - 1
            addEvent(.gap, "\(missed) minute\(missed == 1 ? "" : "s") not received by the phone. Automatic SD recovery is pending.", at: last.date.addingTimeInterval(30))
        }
        let m = Minute(rec); context.insert(m); m.run = run
        if run.deviceID == nil { run.deviceID = t.deviceID }
        lastMinuteEnd = end
        recent.append(rec); if recent.count > 240 { recent.removeFirst(recent.count - 240) }

        if rec.physics {
            if Health.isStuckAtZero(recent) {
                addEvent(.stuckZero, "Three physics minutes with no coincidences. Check high voltage and cables.", at: end)
                Alerts.post(.stuckZero, "Three minutes in a row with zero coincidences. Check high voltage and the SiPM cables.")
            } else if Health.isJump(latest: rec, recent: Array(recent.dropLast())) {
                addEvent(.jump, "\(rec.coincidences) coincidences, far from the recent median.", at: end)
                Alerts.post(.jump, "\(rec.coincidences) coincidences this minute, far outside the recent range.")
            }
        }
        if Date().timeIntervalSince(lastHealthCheck) > 3600, run.physicsMinutes >= 60 {
            lastHealthCheck = Date()
            if let bad = Health.report(run.records).first(where: { $0.level == .poor }) {
                Alerts.post(.health, "\(MinuteRecord.channelNames[bad.channel]) varies \(String(format: "%.1f", bad.fano))× more than counting statistics allow. Look for interference or a noisy threshold.")
            }
        }
        Alerts.armOverdue(lastSample: end)
        try? context.save()
        if Date().timeIntervalSince(lastExport) > 300, cloud.isConfigured { lastExport = Date(); cloud.save(run) }
        publishWidget()
    }

    private func detectStateEvents(_ t: Telemetry) {
        guard let p = previous else { return }
        if p.bootID != t.bootID || p.deviceID != t.deviceID {
            addEvent(.reboot, "New detector session. Counting restarts after setup.", at: Date()); return
        }
        let wifiOff = t.flags & 16 != 0, wasOff = p.flags & 16 != 0
        if wifiOff != wasOff { addEvent(wifiOff ? .wifiOff : .wifiOn, wifiOff ? "Wi‑Fi switched off for quiet counting." : "Wi‑Fi switched on.", at: Date()) }
        if t.hv != p.hv { addEvent(.hvChange, String(format: "HV byte 0x%02X → 0x%02X", p.hv, t.hv), at: Date()) }
        let sdOK = t.status & 2 != 0, wasSD = p.status & 2 != 0
        if wasSD && !sdOK {
            addEvent(.sdProblem, "SD card no longer mounted. Only the phone is recording.", at: Date())
            Alerts.post(.sdProblem, "The detector's SD card is no longer mounted. Only the phone copy is being recorded.")
        }
    }

    func addEvent(_ kind: EventKind, _ detail: String, at date: Date) {
        guard let run = currentRun else { return }
        let e = RunEvent(date: date, kind: kind, detail: detail); context.insert(e); e.run = run
    }

    /// Phase shown everywhere, including "overdue" when minutes stop arriving.
    func refreshPhase() {
        guard logging else { phase = .stopped; return }
        if !demo, link.state == .connected, lastSeen.map({ Date().timeIntervalSince($0) > 30 }) ?? true { link.refresh() }
        let newPhase: Phase
        switch link.state {
        case .searching, .idle, .bluetoothOff, .unauthorized: newPhase = lastMinuteEnd.map { Date().timeIntervalSince($0) > Double(Alerts.overdueMinutes * 60) + 60 } == true ? .overdue : .searching
        case .connecting: newPhase = .connecting
        case .connected:
            if let end = lastMinuteEnd, Date().timeIntervalSince(end) > Double(Alerts.overdueMinutes * 60) + 60 { newPhase = .overdue }
            else if let t = latest { newPhase = t.transition || t.flags & 32 == 0 ? .settling : t.physicsReady ? .physics : .setup }
            else { newPhase = .connecting }
        }
        syncGapsIfNeeded()
        let before = phase
        phase = demo ? .physics : newPhase
        live.update(activityState())
        if before != phase { publishWidget() }
    }

    /// Estimated time left before Wi‑Fi turns off (120 s after the AP starts, ~13 s after boot) plus HV settling.
    var setupEnds: Date? {
        guard let t = latest, t.flags & 16 == 0, !status.wifiKeepOn, let seen = lastSeen else { return nil }
        let remaining = 146_000 - Double(t.uptime)
        return remaining > 0 ? seen.addingTimeInterval(remaining / 1000) : nil
    }

    // MARK: Live Activity + widgets

    private func activityState() -> MuonActivity.ContentState {
        let pairs = recent.last.map { Array($0.counts.prefix(3)) } ?? []
        return MuonActivity.ContentState(phase: phase, runName: currentRun?.name ?? "MuonP4", pairs: pairs, recent: recentTotals(30),
                                         recentPairs: (0..<3).map { ch in recentSeries(30) { $0.counts.count > ch ? $0.counts[ch] : 0 } },
                                         temperature: recent.last?.temperature, pressure: recent.last?.pressure,
                                         sampleDate: lastMinuteEnd, setupEnds: setupEnds, loggingSince: currentRun?.start ?? Date())
    }

    /// Minute totals for the last n minutes, oldest first, -1 where no physics minute was received.
    func recentTotals(_ n: Int) -> [Int] { recentSeries(n) { $0.coincidences } }

    /// Any per-minute value for the last n minutes, oldest first, -1 where no physics minute was received.
    func recentSeries(_ n: Int, _ value: (MinuteRecord) -> Int) -> [Int] {
        RunRecovery.series(recent, count: n, value: value)
    }

    var pressureChange3h: Double? {
        guard let last = recent.last, let p = last.pressure,
              let old = recent.first(where: { last.epoch - $0.epoch <= 3 * 3600 && $0.pressure != nil }), last.epoch - old.epoch > 1800 else { return nil }
        return p - (old.pressure ?? p)
    }

    var sessionTotals: (muons: Int, minutes: Int, pairs: [Int]) {
        guard let run = currentRun else { return (0, 0, [0, 0, 0]) }
        let phys = run.minutes.filter(\.physics)
        let pairs = (0..<3).map { ch in phys.reduce(0) { $0 + max($1.counts[ch], 0) } }
        return (pairs.reduce(0, +), phys.count, pairs)
    }

    func publishWidget() {
        let totals = sessionTotals
        let snap = WidgetSnapshot(logging: logging, phase: phase, runName: currentRun?.name ?? "", runStart: currentRun?.start,
                                  pairs: recent.last.map { Array($0.counts.prefix(3)) } ?? [], recent: recentTotals(60),
                                  meanRate: currentRun?.meanRate, pressure: recent.last?.pressure, pressureChange3h: pressureChange3h,
                                  temperature: recent.last?.temperature, sampleDate: lastMinuteEnd,
                                  totalMuons: totals.muons, exposureMinutes: totals.minutes)
        // WidgetKit budgets background reloads: reload on state changes, otherwise at most every 5 minutes.
        let reload = snap.logging != lastWidget?.logging || snap.phase != lastWidget?.phase || Date().timeIntervalSince(lastWidgetReload) > 300
        if reload { lastWidgetReload = Date() }
        lastWidget = snap
        SharedStore.save(snap, reload: reload)
    }

    // MARK: detector commands

    func refreshStatus() async throws {
        let d = try await link.command("status")
        status = DetectorStatus(d)
        if let run = currentRun, !status.label.isEmpty {
            run.detectorLabel = status.label
            if Self.isDefaultName(run.name) { run.name = status.label }
        }
    }

    func startPhysicsRun() async throws {
        _ = try await link.command("start_physics")
        try? await refreshStatus()
    }

    func syncClock() async throws {
        _ = try await link.command("time", ["epoch": Int(Date().timeIntervalSince1970)])
        try await refreshStatus()
    }

    func setWifiKeepOn(_ on: Bool) async throws {
        _ = try await link.command("wifi_keep", ["enable": on ? 1 : 0])
        try await refreshStatus()
    }

    /// Renames a run. For the live run the detector label is changed too, which
    /// renames the active SD files (muon_… and env_…) on the card.
    func rename(_ run: Run, to name: String, sendToDetector: Bool) async throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let old = run.name
        run.name = clean
        let e = RunEvent(date: Date(), kind: .label, detail: "\(old) → \(clean)"); context.insert(e); e.run = run
        if sendToDetector, run.isLive, link.controlsReady {
            _ = try await link.command("label", ["label": RunLabel.sanitize(clean)])
            try await refreshStatus()
            run.detectorLabel = status.label
        }
        try? context.save()
        if cloud.isConfigured { cloud.save(run) }
    }

    func setTags(_ run: Run, _ tags: [String]) {
        run.tags = tags; try? context.save()
        if cloud.isConfigured { cloud.save(run) }
    }

    // MARK: SD card

    private func syncGapsIfNeeded() {
        guard logging, !demo, !syncing, link.controlsReady, let sample = latest,
              Date() >= nextTransport, let run = currentRun else { return }
        syncing = true
        syncTask = Task { [weak self] in
            guard let self else { return }
            defer { self.syncing = false; self.syncTask = nil }
            do {
                let boot = String(sample.bootID)
                if self.capabilityBoot != boot {
                    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
                    do {
                        let hello = try await self.link.command("hello", ["app": appVersion])
                        guard let device = hello["device"] as? String,
                              RecordIntegrity.deviceKey(device) == RecordIntegrity.deviceKey(sample.deviceID),
                              hello["boot"] as? String == boot else { throw LinkError("Detector identity changed") }
                        if self.firmwareIdentity["device"] != device {
                            self.journalEnds = [:]; self.journalHeaders = [:]
                        }
                        self.firmwareIdentity = hello.mapValues { "\($0)" }
                        self.recoverySchema = hello["schema"] as? Int ?? 0
                        self.capabilityBoot = boot; self.nextJournalScan = .distantPast
                    } catch {
                        // Only an explicit old-firmware response establishes legacy capability.
                        if error.localizedDescription.contains("unknown operation") {
                            self.recoverySchema = 0; self.capabilityBoot = boot
                        } else { throw error }
                    }
                }
                if self.recoverySchema >= 5 {
                    try await self.syncIndexedRecords(run, sample: sample)
                    try await self.uploadLocations(device: sample.deviceID)
                    if Date() >= self.nextLocationRead {
                        let files = try await self.link.listFiles()
                        let boots = Set(run.minutes.map(\.bootID))
                        for file in files where boots.contains(file.name.replacingOccurrences(of: "locations_", with: "").replacingOccurrences(of: ".csv", with: "")) && file.name.hasPrefix("locations_") {
                            let url = try await self.link.download(name: file.name, progress: { _, _ in })
                            let text = try String(contentsOf: url, encoding: .utf8)
                            self.mergeLocations(run, text: text)
                        }
                        self.nextLocationRead = Date().addingTimeInterval(300)
                    }
                } else if self.needsGapSync, Date() >= self.nextSyncAttempt {
                    _ = try await self.recoverFromDetector(run, progress: { _, _ in })
                    self.needsGapSync = RunRecovery.hasGap(run.records)
                    self.nextSyncAttempt = Date().addingTimeInterval(300)
                }
                if self.status.logFile.isEmpty { try await self.refreshStatus() }
                if self.issue?.hasPrefix("Data sync will retry:") == true { self.issue = nil }
                self.nextTransport = Date().addingTimeInterval(5)
            } catch {
                self.nextTransport = Date().addingTimeInterval(30)
                if !Task.isCancelled { self.issue = "Data sync will retry: \(error.localizedDescription)" }
            }
        }
    }

    private func syncIndexedRecords(_ run: Run, sample: Telemetry) async throws {
        let currentBoot = String(sample.bootID)
        if Date() >= nextJournalScan {
            // Include previous/intervening boots, not just the currently active log.
            let files = try await link.listFiles()
            for file in files where file.name.hasPrefix("records_") && file.name.hasSuffix(".csv") {
                let boot = String(file.name.dropFirst(8).dropLast(4))
                guard UInt64(boot) != nil else { continue }
                guard file.modified.timeIntervalSince1970 < 1.6e9 || file.modified >= run.start.addingTimeInterval(-60) || run.minutes.contains(where: { $0.bootID == boot }) else { continue }
                do {
                    let manifest = try await link.command("journal", ["boot": boot, "seq": 0])
                    journalEnds[boot] = manifest["last"] as? Int ?? 0
                } catch {
                    if !error.localizedDescription.contains("journal unavailable") { throw error }
                }
            }
            nextJournalScan = Date().addingTimeInterval(300)
        }
        journalEnds[currentBoot] = Int(sample.sequence)
        var budget = 8
        let boots = [currentBoot] + journalEnds.keys.filter { $0 != currentBoot }.sorted()
        for boot in boots {
            let sameBoot = run.minutes.filter { $0.bootID == boot && $0.sequence > 0 }
            let first = sameBoot.map(\.sequence).min() ?? 1
            let last = journalEnds[boot] ?? 0
            guard first <= last else { continue }
            if journalHeaders[boot] == nil { journalHeaders[boot] = try await link.readRecord(boot: boot, sequence: 0) }
            let complete = Set(sameBoot.filter { $0.diagnostics["schema"] == "5" }.map(\.sequence))
            for sequence in first...last where !complete.contains(sequence) {
                let key = run.id.uuidString + "-" + boot + "-" + String(sequence)
                if let until = deferredRecords[key], until > Date() { continue }
                try Task.checkCancellation()
                guard logging, currentRun?.id == run.id else { return }
                budget -= 1
                let text: String
                do { text = try await link.readRecord(boot: boot, sequence: sequence) }
                catch {
                    if error.localizedDescription.contains("record unavailable") || error.localizedDescription.contains("record read failed") {
                        // A missing/corrupt SD row must not hold up every later row.
                        deferredRecords[key] = Date().addingTimeInterval(300)
                        if budget == 0 { return }; continue
                    }
                    throw error
                }
                guard var row = SDLog.parseMuon((journalHeaders[boot] ?? "") + text, fileName: "records_" + boot + ".csv").minutes.first,
                      row.bootID == boot, row.sequence == sequence,
                      RecordIntegrity.deviceKey(row.diagnostics?["device_id"] ?? "") == RecordIntegrity.deviceKey(sample.deviceID) else { throw LinkError("Recovery record identity mismatch") }
                row.diagnostics?["transport"] = "SD_backfill"
                if let stored = sameBoot.first(where: { $0.sequence == sequence }) {
                    let old = stored.diagnostics
                    stored.diagnostics = (row.diagnostics ?? [:]).merging(old.filter { $0.key.hasPrefix("location_") || $0.key == "fix_epoch_ms" }) { _, old in old }
                    stored.diagnostics["transport"] = stored.fromSD ? "SD_backfill" : "BLE"
                    stored.diagnostics["acquisition"] = stored.fromSD ? "recovered" : "live"
                    stored.diagnostics["sd_recovered"] = stored.fromSD ? "1" : "0"
                    stored.counts = row.counts; stored.physics = row.physics; stored.intervalMS = row.intervalMS
                    if row.epoch > 1.6e9 { stored.epoch = row.epoch }
                    else { stored.diagnostics["utc_estimated"] = old["utc_estimated"] ?? "1" }
                    stored.temperature = row.temperature; stored.pressure = row.pressure
                } else {
                    if row.epoch <= 1.6e9, let end = Double(row.diagnostics?["uptime_ms"] ?? "") {
                        if boot == currentBoot {
                            row.epoch = Date().timeIntervalSince1970 - (Double(sample.uptime) - end) / 1000
                        } else if let anchor = sameBoot.first(where: { $0.diagnostics["uptime_ms"] != nil }),
                                  let uptime = Double(anchor.diagnostics["uptime_ms"] ?? "") {
                            row.epoch = anchor.epoch + (end - uptime) / 1000
                        }
                        row.diagnostics?["utc_estimated"] = "1"
                    }
                    // With no UTC or phone anchor, leave the row on SD for explicit
                    // import. Do not invent a location or merge it into this run.
                    guard row.epoch >= run.start.timeIntervalSince1970 - 60,
                          row.epoch <= (run.end ?? Date()).timeIntervalSince1970 + 60 else {
                        deferredRecords[key] = .distantFuture
                        if budget == 0 { return }; continue
                    }
                    attachHistoricalLocation(to: &row)
                    for assignment in run.stationaryLocations { assignment.apply(to: &row) }
                    row.diagnostics?["acquisition"] = "recovered"; row.diagnostics?["sd_recovered"] = "1"
                    let minute = Minute(row); context.insert(minute); minute.run = run
                }
                try context.save() // Each durable row is the reconnect checkpoint.
                refreshRecoveredViews(run)
                if budget == 0 { return }
            }
        }
    }

    private func attachHistoricalLocation(to row: inout MinuteRecord) {
        guard row.latitude == nil, row.longitude == nil, let fix = location.fix(for: row.date) else { return }
        row.latitude = fix.coordinate.latitude; row.longitude = fix.coordinate.longitude
        row.altitude = fix.verticalAccuracy >= 0 ? fix.altitude : nil; row.horizontalAccuracy = fix.horizontalAccuracy
        if row.diagnostics == nil { row.diagnostics = [:] }
        row.diagnostics?["location_source"] = "gps"
        row.diagnostics?["location_revision"] = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        row.diagnostics?["fix_epoch_ms"] = String(Int64(fix.timestamp.timeIntervalSince1970 * 1000))
    }

    private func uploadLocations(device: String) async throws {
        let runs = try context.fetch(FetchDescriptor<Run>())
        var budget = 8
        for run in runs where RecordIntegrity.deviceKey(run.deviceID ?? "") == RecordIntegrity.deviceKey(device) {
            for minute in run.sortedMinutes {
                guard let lat = minute.latitude, let lon = minute.longitude,
                      let revision = minute.diagnostics["location_revision"], revision != minute.locationSyncedRevision,
                      UInt64(minute.bootID) != nil, minute.sequence > 0, minute.diagnostics["schema"] == "5" else { continue }
                if let until = deferredLocations[revision], until > Date() { continue }
                try Task.checkCancellation()
                let reply: [String: Any]
                do { reply = try await link.command("location", ["boot": minute.bootID, "seq": minute.sequence, "rev": revision,
                    "lat": Int64((lat * 1e7).rounded()), "lon": Int64((lon * 1e7).rounded()),
                    "fix": Int64(minute.diagnostics["fix_epoch_ms"] ?? "0") ?? 0,
                    "acc": minute.horizontalAccuracy.map { Int(($0 * 100).rounded()) } ?? -1,
                    "alt": minute.altitude.map { Int(($0 * 100).rounded()) } ?? -100000000,
                    "src": minute.diagnostics["location_source"] == "manual_stationary" ? 1 : 0]) }
                catch {
                    if error.localizedDescription.contains("record absent") {
                        deferredLocations[revision] = Date().addingTimeInterval(300)
                        budget -= 1; if budget == 0 { return }; continue
                    }
                    throw error
                }
                guard reply["rev"] as? String == revision else { throw LinkError("Location acknowledgement mismatch") }
                minute.locationSyncedRevision = revision; try context.save()
                budget -= 1; if budget == 0 { return }
            }
        }
    }

    private func refreshRecoveredViews(_ run: Run) {
        guard currentRun?.id == run.id else { return }
        let records = run.records
        recent = Array(records.suffix(240)); lastMinuteEnd = recent.last?.date
        seen = Set(records.filter { !$0.bootID.isEmpty && $0.sequence >= 0 }.map { "\($0.bootID)-\($0.sequence)" })
        needsGapSync = RunRecovery.hasGap(records)
        live.update(activityState()); publishWidget()
    }

    func mergeLocations(_ run: Run, text: String) {
        for entry in LocationSidecar.parse(text) {
            guard let minute = run.minutes.first(where: { $0.bootID == entry.boot && $0.sequence == entry.sequence }),
                  minute.latitude == nil || minute.diagnostics["location_revision"] == entry.revision else { continue }
            minute.latitude = entry.latitude; minute.longitude = entry.longitude
            minute.altitude = entry.altitude; minute.horizontalAccuracy = entry.accuracy
            minute.diagnostics["location_source"] = entry.source
            minute.diagnostics["location_revision"] = entry.revision
            minute.diagnostics["fix_epoch_ms"] = entry.epochMS
            minute.locationSyncedRevision = entry.revision
        }
        try? context.save(); refreshRecoveredViews(run)
    }

    func assignStationaryLocation(_ run: Run, from start: Date, to end: Date, latitude: Double, longitude: Double) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude), start <= end else { throw LinkError("Enter valid coordinates and dates") }
        let assignment = StationaryLocation(start: start.timeIntervalSince1970, end: end.timeIntervalSince1970, latitude: latitude, longitude: longitude)
        run.stationaryLocations.append(assignment)
        for minute in run.minutes {
            var row = minute.record; assignment.apply(to: &row)
            minute.latitude = row.latitude; minute.longitude = row.longitude
            minute.diagnostics = row.diagnostics ?? [:]
        }
        try context.save(); refreshRecoveredViews(run)
        if cloud.isConfigured { cloud.save(run) }
        nextTransport = .distantPast; syncGapsIfNeeded()
    }

    /// Downloads the live SD log over Bluetooth and fills minutes the phone missed.
    func fillFromDetector(_ run: Run, progress: @escaping (Int, Int) -> Void) async throws -> Int {
        guard !syncing else { throw LinkError("SD recovery is already running") }
        syncing = true
        defer { syncing = false }
        return try await recoverFromDetector(run, progress: progress)
    }

    private func recoverFromDetector(_ run: Run, progress: @escaping (Int, Int) -> Void) async throws -> Int {
        try await refreshStatus()
        guard !status.logFile.isEmpty else { throw LinkError("The detector has no active SD log") }
        let url = try await link.download(name: status.logFile, progress: progress)
        let text = try String(contentsOf: url, encoding: .utf8)
        var env: [SDLog.EnvRow] = []
        if !status.envFile.isEmpty, let e = try? await link.download(name: status.envFile, progress: { _, _ in }) {
            env = SDLog.parseEnv((try? String(contentsOf: e, encoding: .utf8)) ?? "")
        }
        try Task.checkCancellation()
        var added = fill(run, with: SDLog.parseMuon(text, fileName: status.logFile, env: env).minutes)
        // A reboot or label change can rotate the active file while the phone is away.
        if RunRecovery.hasGap(run.records) {
            let files = try await link.listFiles()
            for file in files where file.name.hasPrefix("muon_") && file.name != status.logFile &&
                (file.modified >= run.start || file.modified.timeIntervalSince1970 <= 0) {
                try Task.checkCancellation()
                let old = try await link.download(name: file.name, progress: progress)
                let rows = SDLog.parseMuon(try String(contentsOf: old, encoding: .utf8), fileName: file.name).minutes
                added += fill(run, with: rows)
                if !RunRecovery.hasGap(run.records) { break }
            }
        }
        return added
    }

    /// Adds SD minutes that the phone did not receive. Returns how many were added.
    @discardableResult
    func fill(_ run: Run, with sd: [MinuteRecord]) -> Int {
        let missing = SDLog.missingMinutes(phone: run.records, sd: sd)
        for var r in missing {
            if currentRun?.id == run.id { attachHistoricalLocation(to: &r) }
            for assignment in run.stationaryLocations { assignment.apply(to: &r) }
            if r.diagnostics == nil { r.diagnostics = [:] }
            r.diagnostics?["transport"] = "SD_backfill"; r.diagnostics?["acquisition"] = "recovered"; r.diagnostics?["sd_recovered"] = "1"
            let m = Minute(r); context.insert(m); m.run = run
        }
        if !missing.isEmpty {
            let e = RunEvent(date: Date(), kind: .sdFilled, detail: "\(missing.count) minutes added from the SD card"); context.insert(e); e.run = run
        }
        try? context.save()
        if cloud.isConfigured { cloud.save(run) }
        if currentRun?.id == run.id {
            let records = run.records
            recent = Array(records.suffix(240))
            seen = Set(records.filter { !$0.bootID.isEmpty && $0.sequence >= 0 }.map { "\($0.bootID)-\($0.sequence)" })
            lastMinuteEnd = recent.last?.date
            needsGapSync = RunRecovery.hasGap(records)
            live.update(activityState()); publishWidget()
        }
        return missing.count
    }

    /// Imports an SD log as its own run, or fills an overlapping phone run.
    func importSD(text: String, fileName: String, envText: String?, locationTexts: [String] = []) -> String {
        let env = envText.map(SDLog.parseEnv) ?? []
        let parsed = SDLog.parseMuon(text, fileName: fileName, env: env)
        guard let first = parsed.minutes.first, let last = parsed.minutes.last else { return "\(fileName) has no measurement rows." }
        let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        if let match = runs.first(where: { r in r.source == "phone" && (r.deviceID == nil || first.diagnostics?["device_id"] == nil || RecordIntegrity.deviceKey(r.deviceID ?? "") == RecordIntegrity.deviceKey(first.diagnostics?["device_id"] ?? "")) && overlap(r, first.epoch, last.epoch) > 0.5 }) {
            let n = fill(match, with: parsed.minutes)
            for text in locationTexts { mergeLocations(match, text: text) }
            return "\(n) missing minutes added to \(match.name)."
        }
        if runs.contains(where: { $0.sdFileName == fileName }) { return "\(fileName) is already imported." }
        let run = Run(name: parsed.label ?? fileName, start: first.date, source: "sd")
        run.deviceID = first.diagnostics?["device_id"]
        run.end = last.date; run.sdFileName = fileName; run.detectorLabel = parsed.label
        context.insert(run)
        for r in parsed.minutes { let m = Minute(r); context.insert(m); m.run = run }
        try? context.save()
        for text in locationTexts { mergeLocations(run, text: text) }
        return "Imported \(parsed.minutes.count) minutes as \(run.name)."
    }

    private func overlap(_ r: Run, _ a: Double, _ b: Double) -> Double {
        let s = r.start.timeIntervalSince1970, e = (r.end ?? Date()).timeIntervalSince1970
        let o = min(e, b) - max(s, a)
        return o <= 0 ? 0 : o / max(b - a, 60)
    }

    func delete(_ run: Run) {
        guard !run.isLive else { return }
        context.delete(run); try? context.save()
    }
}
