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
    @State private var wifi: [String: String] = [:]

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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 1).id(TabScrollTop.anchor(.detector)).accessibilityHidden(true)
                // Warning: pink is allowed here, it is an alert about destructive changes.
                Label("Changes stop the current minute. It is discarded, high voltage settles for 10 s and counting restarts.", systemImage: "exclamationmark.triangle")
                    .font(Typography.footnote).foregroundStyle(Palette.alert)
                    .fixedSize(horizontal: false, vertical: true)
                    .panel(padding: 12, fill: Palette.alert.opacity(0.08))

                SectionLabel("High voltage · MAX1932")
                hvCard
                SectionLabel("DAC · DACx578")
                dacCard
                SectionLabel("FPGA")
                fpgaCard
                SectionLabel("Counters · now / last min / boot")
                countersCard
                SectionLabel("Radio diagnostics")
                radioCard
                SectionLabel("Environment sensor")
                environmentCard
                SectionLabel("Telemetry")
                telemetryCard
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
            .tabScrollTop(.detector)
        .background(Palette.background)
        .navigationTitle("Expert console")
        .disabled(busy || !app.link.controlsReady)
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            Button("Apply", role: .destructive) { apply() }
        } message: { Text("This interrupts counting. Setup and transitions are never counted as physics.") }
        .alert("Detector", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
        .task { if let t = app.latest { hv = Int(t.hv) }; await refresh() }
    }

    private var hvCard: some View {
        VStack(spacing: 12) {
            HStack {
                Button { hv = max(1, hv - 1) } label: { Image(systemName: "minus") }.buttonStyle(.muonIcon).accessibilityLabel("Lower HV byte")
                Spacer()
                Text(String(format: "0x%02X", hv)).font(Typography.mono(40, .medium, relativeTo: .largeTitle)).foregroundStyle(Palette.ink)
                    .accessibilityLabel("HV byte \(hv)")
                Spacer()
                Button { hv = min(255, hv + 1) } label: { Image(systemName: "plus") }.buttonStyle(.muonIcon).accessibilityLabel("Raise HV byte")
            }
            if let t = app.latest {
                HStack {
                    Text("Current").font(Typography.footnote).foregroundStyle(Palette.secondaryText)
                    Spacer()
                    Text(String(format: "0x%02X", t.hv)).font(Typography.mono(13, .regular, relativeTo: .footnote)).foregroundStyle(Palette.secondaryText)
                }
            }
            HStack(spacing: 10) {
                Button("Turn HV off", role: .destructive) { pending = .hvOff }.buttonStyle(.muonDestructive)
                Button(String(format: "Apply 0x%02X", hv)) { pending = .hv(hv) }.buttonStyle(.muonPrimary)
            }
        }.card(edge: .bright)
    }

    private var dacCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Channel").font(Typography.subheadline)
                Spacer()
                Picker("Channel", selection: $dacChannel) {
                    ForEach(0..<8, id: \.self) { Text("\($0)\($0 < 4 ? " · SiPM bias" : " · threshold")").tag($0) }
                }.pickerStyle(.menu).tint(Palette.lilac).labelsHidden()
            }
            HStack {
                Text("Code").font(Typography.subheadline)
                Spacer()
                Text(String(format: "0x%03X", Int(dacValue))).font(Typography.monoBody)
            }
            Slider(value: $dacValue, in: 0...1023, step: 1).tint(Palette.violet)
            HStack(spacing: 10) {
                Button("Restore startup") { pending = .dacStartup }.buttonStyle(.muonSecondary)
                Button(String(format: "Set DAC %d", dacChannel)) { pending = .dac(dacChannel, Int(dacValue)) }.buttonStyle(.muonPrimary)
            }
            if !app.status.dac.isEmpty {
                Text(app.status.dac.enumerated().map { String(format: "%d:%03X", $0.offset, $0.element) }.joined(separator: " "))
                    .font(Typography.monoCaption).foregroundStyle(Palette.secondaryText)
            }
            Text("Startup profile: channels 0–3 at 0x2F1 (SiPM bias, adjusted by the detector's temperature compensation), channels 4–7 at 0x070 (thresholds).")
                .font(Typography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    /// Bitstream name, if the firmware status reports one (current firmware does not).
    private var bitstream: String? {
        let raw = app.status.raw
        return raw["bitstream"] ?? raw["fpga_bitstream"] ?? raw["fpga"]
    }

    private var fpgaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "memorychip").foregroundStyle(Palette.lilac)
                VStack(alignment: .leading, spacing: 2) {
                    if let bitstream {
                        Text(bitstream).font(Typography.monoBody).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Text("Embedded bitstream").font(Typography.subheadline)
                    }
                    Text(app.latest.map { $0.status & 1 != 0 ? "Loaded" : "Not ready" } ?? "Unknown")
                        .font(Typography.caption).foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                Button("Reload", role: .destructive) { pending = .fpga }.buttonStyle(.muonDestructiveCompact)
            }
            Text("HV off → load the embedded bitstream → startup DAC and HV → settle.")
                .font(Typography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
        }.card()
    }

    private var countersCard: some View {
        VStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                if i > 0 { RowDivider() }
                HStack {
                    ChannelLabel(channel: i, size: 14, color: i < 4 ? Palette.ink : Palette.muted)
                    Spacer(minLength: 8)
                    Text("\(counters.live[safe: i].map(String.init) ?? "—") / \(counters.last[safe: i].map(String.init) ?? "—") / \(counters.total[safe: i] ?? "—")")
                        .font(Typography.mono(13, .regular, relativeTo: .footnote)).foregroundStyle(i < 3 ? Palette.data : Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
            RowDivider(leading: 0)
            HStack {
                Text("Boot totals include setup minutes. Physics-only totals are on Now.").font(Typography.caption).foregroundStyle(Palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.muonIcon).accessibilityLabel("Refresh counters")
            }
            .padding(12)
        }.card(padding: 0)
    }

    /// Stub until the firmware grows a `wifi_status` command (see README, roadmap).
    /// If a detector already answers it, the raw key/value pairs are shown.
    private var radioCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Palette.lilac)
                Text("Wi‑Fi access point").font(Typography.subheadline)
                Spacer()
                Text(app.latest.map { $0.flags & 16 != 0 ? "off" : "on" } ?? "—").font(Typography.monoCaption).foregroundStyle(Palette.secondaryText)
            }
            if wifi.isEmpty {
                Text("Needs firmware wifi_status command").font(Typography.monoCaption).foregroundStyle(Palette.muted)
                Text("Channel, connected stations and TX power will appear here once the detector reports them.")
                    .font(Typography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(wifi.sorted(by: { $0.key < $1.key }), id: \.key) { kv in
                    HStack {
                        Text(kv.key).font(Typography.monoCaption).foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Text(kv.value).font(Typography.monoCaption).lineLimit(1)
                    }
                }
            }
        }.card()
    }

    private var environmentCard: some View {
        VStack(spacing: 8) {
            if let t = environment["temp_c"] as? Double { kv("Temperature", String(format: "%.2f °C", t), Palette.temperature) }
            if let p = environment["pressure_hpa"] as? Double { kv("Pressure", String(format: "%.2f hPa", p), Palette.pressure) }
            if let h = environment["humidity_pct"] as? Double { kv("Humidity", String(format: "%.1f %%", h), Palette.ink) }
            if environment.isEmpty { Text("No reading yet").font(Typography.caption).foregroundStyle(Palette.secondaryText).frame(maxWidth: .infinity, alignment: .leading) }
        }.card()
    }

    private var telemetryCard: some View {
        VStack(spacing: 6) {
            if let t = app.latest {
                kv("Boot ID", String(t.bootID))
                kv("Sequence", "\(t.sequence)")
                kv("Flags", String(format: "0x%02X", t.flags))
                kv("Status", String(format: "0x%04X", t.status))
                kv("Device", t.deviceID)
                if let r = app.link.rssi { kv("RSSI", "\(r) dBm") }
            }
            ForEach(app.status.raw.sorted(by: { $0.key < $1.key }), id: \.key) { pair in
                kv(pair.key, pair.value)
            }
        }.card()
    }

    private func kv(_ k: String, _ v: String, _ tint: Color = Palette.ink) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(Typography.footnote).foregroundStyle(Palette.secondaryText).lineLimit(1)
            Spacer(minLength: 8)
            Text(v).font(Typography.mono(12, .regular, relativeTo: .caption)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func refresh() async {
        guard app.link.controlsReady else { return }
        do {
            try await app.refreshStatus()
            let c = try await app.link.command("counts")
            counters = (c["live"] as? [Int] ?? [], c["last"] as? [Int] ?? [], c["total"] as? [String] ?? [])
            environment = try await app.link.command("environment")
        } catch { message = error.localizedDescription }
        // Optional: firmware without `wifi_status` answers with an error, which is ignored.
        if let w = try? await app.link.command("wifi_status"), w["ok"] as? Bool != false {
            wifi = w.filter { $0.key != "ok" && $0.key != "op" && $0.key != "id" }.mapValues { "\($0)" }
        }
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
