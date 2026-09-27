import SwiftUI

struct DetectorView: View {
    @Environment(AppModel.self) private var app
    @State private var busy: String?
    @State private var message: String?
    @State private var files: [(name: String, size: Int, modified: Date)] = []
    @State private var download: URL?
    @State private var progress = ""
    @State private var confirmPhysics = false
    @State private var renaming = false
    @State private var showPair = false

    private var t: Telemetry? { app.latest }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: 1).id(TabScrollTop.anchor(.detector)).accessibilityHidden(true)
                    connectionCard
                    if app.link.state == .connected, let t {
                        checklist(t)
                        SectionLabel("Run")
                        actions
                        SectionLabel("Files on the SD card")
                        filesCard
                    }
                    if !app.firmwareIdentity.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Firmware & hardware").font(Typography.headline)
                            Text("Firmware " + String((app.firmwareIdentity["firmware"] ?? "unknown").prefix(12)))
                            Text("Hardware " + (app.firmwareIdentity["hardware"] ?? "unknown"))
                            Text("Built " + (app.firmwareIdentity["build_utc"] ?? "unknown"))
                            Text("Record schema " + (app.firmwareIdentity["schema"] ?? "legacy"))
                        }.font(Typography.monoCaption).card()
                    }
                    expertLink
                }
                // Extra scroll-content margins are supplied by the selected tab-bar style.
                .padding(.horizontal, 20).padding(.bottom, 8)
            }
            .tabScrollTop(.detector)
            .background(Palette.background)
            .navigationTitle("Detector")
            .refreshable { await refresh() }
            .sheet(isPresented: $showPair) { PairView() }
            .sheet(isPresented: $renaming) { if let run = app.currentRun { RenameSheet(run: run) } }
            .confirmationDialog("Start a physics run?", isPresented: $confirmPhysics, titleVisibility: .visible) {
                Button("Start physics run") { run("Starting") { try await app.startPhysicsRun() } }
            } message: {
                Text("Wi‑Fi turns off until the next reboot, high voltage cycles off for 3 s and settles for 10 s. The next full minute is the first physics minute.")
            }
            .alert("Detector", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") {} } message: { Text(message ?? "") }
            .task { if app.link.controlsReady { await refresh() } }
        }
    }

    private func run(_ what: String, _ work: @escaping () async throws -> Void) {
        busy = what
        Task { do { try await work() } catch { message = error.localizedDescription }; busy = nil }
    }
    private func refresh() async { try? await app.refreshStatus(); app.link.refresh() }

    private var connectionCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "cpu").font(.system(size: 22, weight: .medium)).foregroundStyle(Palette.lilac)
                .frame(width: 52, height: 52)
                .background(Palette.violet.opacity(0.16), in: ChamferedShape.control(Chamfer.button))
                .overlay { ChamferedShape.control(Chamfer.button).strokeBorder(Palette.hairline, lineWidth: 1) }
            VStack(alignment: .leading, spacing: 2) {
                Text("MuonP4").font(Typography.title2).lineLimit(1)
                Text(connectionText).font(Typography.footnote).foregroundStyle(Palette.secondaryText)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if app.link.state == .connected { PhaseBadge(phase: app.phase) }
            else if !app.logging {
                Button(app.needsPairing ? "Find" : "Connect") { if app.needsPairing { showPair = true } else { app.start() } }
                    .buttonStyle(.muonPrimaryCompact)
            }
        }
        .panel(padding: 16, edge: .bright, cut: 18, fill: Palette.hero)
    }

    private var connectionText: String {
        switch app.link.state {
        case .connected:
            var s = "Connected"
            if app.link.controlsReady { s += " · encrypted" }
            if let t { s += " · up " + (Double(t.uptime) / 1000).hoursMinutes }
            if let r = app.link.rssi { s += r > -70 ? " · signal good" : r > -85 ? " · signal fair" : " · signal weak" }
            return s
        case .connecting: return "Connecting…"
        case .searching: return "Looking nearby. It advertises every 15 s."
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Allow Bluetooth for this app in Settings"
        case .idle: return app.needsPairing ? "No detector paired yet" : "Start logging to connect"
        }
    }

    private func checklist(_ t: Telemetry) -> some View {
        VStack(spacing: 0) {
            check("Scintillator readout", t.status & 1 != 0 ? "FPGA loaded" : "FPGA not ready", t.status & 1 != 0)
            RowDivider(leading: 46)
            check("High voltage", t.flags & 32 != 0 ? "Settled · SiPMs biased" : "Settling or off", t.flags & 32 != 0)
            RowDivider(leading: 46)
            check("SD card", t.status & 2 == 0 ? "Not mounted. Only the phone is recording." : (t.status & 4 != 0 ? "Writing each minute" : "Mounted, last write failed"), t.status & 6 == 6)
            RowDivider(leading: 46)
            check("Radio quiet", t.flags & 16 != 0 ? "Wi‑Fi off until next reboot" : (app.status.wifiKeepOn ? "Wi‑Fi held on" : "Wi‑Fi on for setup"), t.flags & 16 != 0)
            RowDivider(leading: 46)
            HStack {
                check("Clock", t.flags & 8 != 0 ? "Synced" : "Not synced since reboot", t.flags & 8 != 0)
                if t.flags & 8 == 0 {
                    Button("Sync") { run("Syncing") { try await app.syncClock() } }.buttonStyle(.muonSecondaryCompact).padding(.trailing, 12).disabled(!app.link.controlsReady)
                }
            }
        }
        .card(padding: 0)
    }

    private func check(_ title: String, _ detail: String, _ ok: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle" : "exclamationmark.circle").font(.system(size: 20)).foregroundStyle(ok ? Palette.physics : Palette.muted)
            VStack(alignment: .leading, spacing: 1) { Text(title).font(Typography.subheadline).lineLimit(1); Text(detail).font(Typography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true) }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { confirmPhysics = true } label: {
                Label(busy == "Starting" ? "Starting…" : "Start physics run", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.muonPrimary).disabled(!app.link.controlsReady || busy != nil)
            HStack(spacing: 10) {
                tile("Keep Wi‑Fi on", "wifi", disabled: t.map { $0.flags & 16 != 0 } ?? true) { run("Wi‑Fi") { try await app.setWifiKeepOn(!app.status.wifiKeepOn) } }
                tile("Name this run", "pencil", disabled: app.currentRun == nil) { renaming = true }
            }
            Text("Wi‑Fi turns off 120 s after boot when nobody is connected to it, and stays off until the next reboot. Keeping it on means no physics minutes are recorded.")
                .font(Typography.caption).foregroundStyle(Palette.secondaryText)
            if let label = app.status.label.isEmpty ? nil : app.status.label {
                Text("Detector label \(label) · \(app.status.logFile)").font(Typography.mono(11, .regular, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private func tile(_ title: String, _ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon).foregroundStyle(Palette.lilac)
                Text(title).font(Typography.subheadline).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(padding: 12, cut: 12)
        }.buttonStyle(.plain).disabled(disabled || !app.link.controlsReady || busy != nil)
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if files.isEmpty {
                Button { run("Listing") { files = try await app.link.listFiles() } } label: {
                    Label(busy == "Listing" ? "Reading card…" : "List files", systemImage: "sdcard").frame(maxWidth: .infinity)
                }.buttonStyle(.muonSecondary).disabled(!app.link.controlsReady || busy != nil)
            }
            ForEach(files, id: \.name) { f in
                Button {
                    run("Downloading") {
                        let url = try await app.link.download(name: f.name) { a, b in progress = "\(a / 1024) / \(b / 1024) KB" }
                        download = url
                        if f.name.hasPrefix("muon_") {
                            let envName = "env_" + f.name.dropFirst(5)
                            var env: URL?
                            if files.contains(where: { $0.name == envName }) { env = try? await app.link.download(name: envName) { _, _ in } }
                            message = app.importSD(text: try String(contentsOf: url, encoding: .utf8), fileName: f.name,
                                                   envText: env.flatMap { try? String(contentsOf: $0, encoding: .utf8) })
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).font(Typography.monoCaption).lineLimit(1)
                            Text("\(f.size / 1024) KB · \(f.modified.formatted(date: .abbreviated, time: .shortened))").font(Typography.raleway(11, .medium, relativeTo: .caption2)).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.circle").foregroundStyle(Palette.lilac)
                    }
                }.buttonStyle(.plain).disabled(busy != nil)
            }
            if busy == "Downloading" { ProgressView(progress).font(Typography.caption) ; Button("Cancel", role: .cancel) { app.link.cancelCommand() } }
            if let download { ShareLink(item: download) { Label("Share \(download.lastPathComponent)", systemImage: "square.and.arrow.up") }.font(Typography.footnote) }
            Text("Downloading a muon log also imports it into Runs, or fills the gaps of the matching phone run.").font(Typography.caption).foregroundStyle(Palette.secondaryText)
        }.card()
    }

    @ViewBuilder private var expertLink: some View {
        if app.expertMode {
            NavigationLink { ExpertConsoleView() } label: {
                HStack {
                    Label("Expert console", systemImage: "slider.horizontal.3").font(Typography.subheadline).foregroundStyle(Palette.ink)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Palette.secondaryText)
                }.card()
            }.buttonStyle(.plain)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "lock").foregroundStyle(Palette.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expert console").font(Typography.subheadline)
                    Text("High voltage, thresholds and FPGA. Turn on Expert mode in Settings.").font(Typography.caption).foregroundStyle(Palette.secondaryText)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay { ChamferedShape.panel().strokeBorder(Palette.secondaryText.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4])) }
        }
    }
}
