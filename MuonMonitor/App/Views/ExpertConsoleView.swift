import SwiftUI

/// High voltage, DAC, FPGA and raw counters. Every change asks for confirmation
/// and is never retried automatically.
struct ExpertConsoleView: View {
    @Environment(AppModel.self) private var app
    @State private var hv: Int = 0xEA
    @State private var dacChannel = 4
    @State private var dacValue: Double = 0x070
    @State private var pending: Change?
    @State private var busy = false
    @State private var message: String?
    @State private var counters: (live: [Int], last: [Int], total: [String]) = ([], [], [])
    @State private var environment: [String: Any] = [:]

    enum Change: Identifiable {
        case hv(Int), hvOff, dac(Int, Int), dacStartup, fpga
        var id: String { title }
        var eventKind: EventKind {
            switch self {
            case .hv, .hvOff: .hvChange
            default: .note
            }
        }
        var title: String {
            switch self {
            case .hv(let v): String(format: "Set HV byte to 0x%02X?", v)
            case .hvOff: "Turn high voltage off?"
            case .dac(let c, let v): String(format: "Set DAC %d to 0x%03X?", c, v)
            case .dacStartup: "Restore startup DAC values?"
            case .fpga: "Reload the FPGA?"
            }
        }
    }

    var body: some View {
        Form {
            Section {
                Label("Changes stop the current minute. It is discarded, high voltage settles for 10 s and counting restarts.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Palette.warning)
            }
            Section("High voltage · MAX1932") {
                HStack {
                    Button { hv = max(1, hv - 1) } label: { Image(systemName: "minus") }.buttonStyle(.glass)
                    Spacer()
                    Text(String(format: "0x%02X", hv)).font(.system(.largeTitle, design: .monospaced)).accessibilityLabel("HV byte \(hv)")
                    Spacer()
                    Button { hv = min(255, hv + 1) } label: { Image(systemName: "plus") }.buttonStyle(.glass)
                }
                if let t = app.latest { LabeledContent("Current", value: String(format: "0x%02X", t.hv)).font(.footnote.monospaced()) }
                HStack {
                    Button("Turn HV off", role: .destructive) { pending = .hvOff }.buttonStyle(.glass)
                    Spacer()
                    Button(String(format: "Apply 0x%02X", hv)) { pending = .hv(hv) }.buttonStyle(.glassProminent)
                }
            }
            Section {
                Picker("Channel", selection: $dacChannel) {
                    ForEach(0..<8, id: \.self) { Text("\($0)\($0 < 4 ? " · SiPM bias" : " · threshold")").tag($0) }
                }
                VStack(alignment: .leading) {
                    HStack { Text("Code"); Spacer(); Text(String(format: "0x%03X", Int(dacValue))).monospaced() }
                    Slider(value: $dacValue, in: 0...1023, step: 1)
                }
                Button(String(format: "Set DAC %d to 0x%03X", dacChannel, Int(dacValue))) { pending = .dac(dacChannel, Int(dacValue)) }
                Button("Restore startup values") { pending = .dacStartup }
                if !app.status.dac.isEmpty {
                    Text(app.status.dac.enumerated().map { String(format: "%d:%03X", $0.offset, $0.element) }.joined(separator: " "))
                        .font(.caption.monospaced()).foregroundStyle(Palette.secondaryText)
                }
            } header: { Text("DAC · DACx578") } footer: {
                Text("Startup profile: channels 0–3 at 0x2F1 (SiPM bias, adjusted by the detector's temperature compensation), channels 4–7 at 0x070 (thresholds).")
            }
            Section("FPGA") {
                Button("Reload FPGA", role: .destructive) { pending = .fpga }
                Text("HV off → load the embedded bitstream → startup DAC and HV → settle.").font(.caption).foregroundStyle(Palette.secondaryText)
            }
            Section("Counters · now / last minute / boot total") {
                ForEach(0..<7, id: \.self) { i in
                    LabeledContent(MinuteRecord.channelNames[i]) {
                        Text("\(counters.live[safe: i].map(String.init) ?? "—") / \(counters.last[safe: i].map(String.init) ?? "—") / \(counters.total[safe: i] ?? "—")")
                            .monospacedDigit()
                    }
                }
                Text("Boot totals include setup minutes. Physics-only totals are on Now.").font(.caption).foregroundStyle(Palette.secondaryText)
                Button("Refresh") { Task { await refresh() } }
            }
            Section("Environment sensor") {
                if let t = environment["temp_c"] as? Double { LabeledContent("Temperature", value: String(format: "%.2f °C", t)) }
                if let p = environment["pressure_hpa"] as? Double { LabeledContent("Pressure", value: String(format: "%.2f hPa", p)) }
                if let h = environment["humidity_pct"] as? Double { LabeledContent("Humidity", value: String(format: "%.1f %%", h)) }
            }
            Section("Telemetry") {
                if let t = app.latest {
                    Group {
                        LabeledContent("Boot ID", value: String(t.bootID))
                        LabeledContent("Sequence", value: "\(t.sequence)")
                        LabeledContent("Flags", value: String(format: "0x%02X", t.flags))
                        LabeledContent("Status", value: String(format: "0x%04X", t.status))
                        LabeledContent("Device", value: t.deviceID)
                        if let r = app.link.rssi { LabeledContent("RSSI", value: "\(r) dBm") }
                    }.font(.footnote.monospaced())
                }
                ForEach(app.status.raw.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                    LabeledContent(pair.key, value: pair.value).font(.caption2.monospaced())
                }
            }
        }
        .navigationTitle("Expert console")
        .disabled(busy || !app.link.controlsReady)
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Apply", role: .destructive) { apply() }
        } message: { Text("This interrupts counting. Setup and transitions are never counted as physics.") }
        .alert("Detector", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
        .task { if let t = app.latest { hv = Int(t.hv) }; await refresh() }
    }

    private func refresh() async {
        guard app.link.controlsReady else { return }
        do {
            try await app.refreshStatus()
            let c = try await app.link.command("counts")
            counters = (c["live"] as? [Int] ?? [], c["last"] as? [Int] ?? [], c["total"] as? [String] ?? [])
            environment = try await app.link.command("environment")
        } catch { message = error.localizedDescription }
    }

    private func apply() {
        guard let change = pending else { return }
        pending = nil; busy = true
        Task {
            do {
                switch change {
                case .hv(let v): _ = try await app.link.command("hv", ["value": v])
                case .hvOff: _ = try await app.link.command("hv", ["value": 0])
                case .dac(let c, let v): _ = try await app.link.command("dac", ["channel": c, "value": v])
                case .dacStartup: _ = try await app.link.command("dac_startup")
                case .fpga: _ = try await app.link.command("fpga")
                }
                app.addEvent(change.eventKind, change.title.replacingOccurrences(of: "?", with: ""), at: Date())
                await refresh()
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
