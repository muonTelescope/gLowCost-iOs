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
        wifiKeepOn = d["wifi_keep"] as? Bool ?? false
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
        logging = true; UserDefaults.standard.set(true, forKey: "logging")
        Alerts.requestPermission()
        location.start(); link.connect()
        phase = .searching
        do { try live.start(activityState()) } catch { issue = "Live Activity could not start: \(error.localizedDescription)" }
        publishWidget()
    }

    func stop() {
        guard logging, !demo else { return }
        logging = false; UserDefaults.standard.set(false, forKey: "logging")
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
        }
        location.start(); link.connect(); phase = .connecting
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
        if link.controlsReady, status.logFile.isEmpty { Task { try? await refreshStatus() } }
    }

    private func record(_ t: Telemetry) {
        guard let run = currentRun else { return }
        let clockSet = t.flags & 8 != 0
        let end = clockSet ? Date(timeIntervalSince1970: TimeInterval(t.epoch)) : Date().addingTimeInterval(-t.sampleAge)
        let fix = location.fix(for: end)
        let rec = MinuteRecord(epoch: end.timeIntervalSince1970, sequence: Int(t.sequence), bootID: String(t.bootID),
                               intervalMS: Int(t.interval), physics: t.physics, counts: t.counts.map(Int.init),
                               temperature: t.temperature, pressure: t.pressure,
                               latitude: fix?.coordinate.latitude, longitude: fix?.coordinate.longitude,
                               altitude: fix.flatMap { $0.verticalAccuracy >= 0 ? $0.altitude : nil },
                               horizontalAccuracy: fix?.horizontalAccuracy, fromSD: false)
        // Missed minutes on the same boot: note the gap; the SD card has them.
        if let last = recent.last, last.bootID == rec.bootID, rec.sequence > last.sequence + 1 {
            let missed = rec.sequence - last.sequence - 1
            addEvent(.gap, "\(missed) minute\(missed == 1 ? "" : "s") not received by the phone. Fill them from the SD card in Run details.", at: last.date.addingTimeInterval(30))
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
        if Date().timeIntervalSince(lastHealthCheck) > 3600, recent.filter(\.physics).count >= 60 {
            lastHealthCheck = Date()
            if let bad = Health.report(recent).first(where: { $0.level == .poor }) {
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
        let newPhase: Phase
        switch link.state {
        case .searching, .idle, .bluetoothOff, .unauthorized: newPhase = lastMinuteEnd.map { Date().timeIntervalSince($0) > Double(Alerts.overdueMinutes * 60) + 60 } == true ? .overdue : .searching
        case .connecting: newPhase = .connecting
        case .connected:
            if let end = lastMinuteEnd, Date().timeIntervalSince(end) > Double(Alerts.overdueMinutes * 60) + 60 { newPhase = .overdue }
            else if let t = latest { newPhase = t.transition || t.flags & 32 == 0 ? .settling : t.physicsReady ? .physics : .setup }
            else { newPhase = .connecting }
        }
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
        guard let end = recent.last?.epoch else { return [] }
        var out = Array(repeating: -1, count: n)
        for r in recent.reversed() {
            let i = n - 1 - Int(((end - r.epoch) / 60).rounded())
            if i < 0 { break }
            if r.physics { out[i] = max(value(r), 0) }
        }
        return out
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

    /// Downloads the live SD log over Bluetooth and fills minutes the phone missed.
    func fillFromDetector(_ run: Run, progress: @escaping (Int, Int) -> Void) async throws -> Int {
        try await refreshStatus()
        guard !status.logFile.isEmpty else { throw LinkError("The detector has no active SD log") }
        let url = try await link.download(name: status.logFile, progress: progress)
        let text = try String(contentsOf: url, encoding: .utf8)
        var env: [SDLog.EnvRow] = []
        if !status.envFile.isEmpty, let e = try? await link.download(name: status.envFile, progress: { _, _ in }) {
            env = SDLog.parseEnv((try? String(contentsOf: e, encoding: .utf8)) ?? "")
        }
        return fill(run, with: SDLog.parseMuon(text, fileName: status.logFile, env: env).minutes)
    }

    /// Adds SD minutes that the phone did not receive. Returns how many were added.
    @discardableResult
    func fill(_ run: Run, with sd: [MinuteRecord]) -> Int {
        let missing = SDLog.missingMinutes(phone: run.records, sd: sd)
        for r in missing { let m = Minute(r); context.insert(m); m.run = run }
        if !missing.isEmpty {
            let e = RunEvent(date: Date(), kind: .sdFilled, detail: "\(missing.count) minutes added from the SD card"); context.insert(e); e.run = run
        }
        try? context.save()
        if cloud.isConfigured { cloud.save(run) }
        return missing.count
    }

    /// Imports an SD log as its own run, or fills an overlapping phone run.
    func importSD(text: String, fileName: String, envText: String?) -> String {
        let env = envText.map(SDLog.parseEnv) ?? []
        let parsed = SDLog.parseMuon(text, fileName: fileName, env: env)
        guard let first = parsed.minutes.first, let last = parsed.minutes.last else { return "\(fileName) has no rows with a synced clock." }
        let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        if let match = runs.first(where: { r in r.source == "phone" && overlap(r, first.epoch, last.epoch) > 0.5 }) {
            let n = fill(match, with: parsed.minutes)
            return "\(n) missing minutes added to \(match.name)."
        }
        if runs.contains(where: { $0.sdFileName == fileName }) { return "\(fileName) is already imported." }
        let run = Run(name: parsed.label ?? fileName, start: first.date, source: "sd")
        run.end = last.date; run.sdFileName = fileName; run.detectorLabel = parsed.label
        context.insert(run)
        for r in parsed.minutes { let m = Minute(r); context.insert(m); m.run = run }
        try? context.save()
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
