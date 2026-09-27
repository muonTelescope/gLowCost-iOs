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
                    connectionCard
                    if app.link.state == .connected, let t {
                        checklist(t)
                        SectionLabel("Run")
                        actions
                        SectionLabel("Files on the SD card")
                        filesCard
                    }
                    expertLink
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
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
            Image(systemName: "cpu").font(.title2).foregroundStyle(Palette.accentSoft)
                .frame(width: 52, height: 52).background(Palette.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("MuonP4").font(.headline)
                Text(connectionText).font(.footnote).foregroundStyle(Palette.secondaryText)
            }
            Spacer()
            if app.link.state == .connected { PhaseBadge(phase: app.phase) }
            else if !app.logging {
                Button(app.needsPairing ? "Find" : "Connect") { if app.needsPairing { showPair = true } else { app.start() } }.buttonStyle(.glassProminent)
            }
        }
        .padding(16).background(Palette.hero, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.accent.opacity(0.2)))
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
            Divider().padding(.leading, 46)
            check("High voltage", t.flags & 32 != 0 ? "Settled · SiPMs biased" : "Settling or off", t.flags & 32 != 0)
            Divider().padding(.leading, 46)
            check("SD card", t.status & 2 == 0 ? "Not mounted. Only the phone is recording." : (t.status & 4 != 0 ? "Writing each minute" : "Mounted, last write failed"), t.status & 6 == 6)
            Divider().padding(.leading, 46)
            check("Radio quiet", t.flags & 16 != 0 ? "Wi‑Fi off until next reboot" : (app.status.wifiKeepOn ? "Wi‑Fi held on" : "Wi‑Fi on for setup"), t.flags & 16 != 0)
            Divider().padding(.leading, 46)
            HStack {
                check("Clock", t.flags & 8 != 0 ? "Synced" : "Not synced since reboot", t.flags & 8 != 0)
                if t.flags & 8 == 0 {
                    Button("Sync") { run("Syncing") { try await app.syncClock() } }.buttonStyle(.glass).padding(.trailing, 12).disabled(!app.link.controlsReady)
                }
            }
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func check(_ title: String, _ detail: String, _ ok: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark.circle" : "exclamationmark.circle").font(.title3).foregroundStyle(ok ? Palette.physics : Palette.warning)
            VStack(alignment: .leading, spacing: 1) { Text(title).font(.subheadline.weight(.medium)); Text(detail).font(.caption).foregroundStyle(Palette.secondaryText) }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { confirmPhysics = true } label: {
                Label(busy == "Starting" ? "Starting…" : "Start physics run", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
            }.buttonStyle(.glassProminent).disabled(!app.link.controlsReady || busy != nil)
            HStack(spacing: 10) {
                tile("Keep Wi‑Fi on", "wifi", disabled: t.map { $0.flags & 16 != 0 } ?? true) { run("Wi‑Fi") { try await app.setWifiKeepOn(!app.status.wifiKeepOn) } }
                tile("Name this run", "pencil", disabled: app.currentRun == nil) { renaming = true }
            }
            Text("Wi‑Fi turns off 120 s after boot when nobody is connected to it, and stays off until the next reboot. Keeping it on means no physics minutes are recorded.")
                .font(.caption).foregroundStyle(Palette.secondaryText)
            if let label = app.status.label.isEmpty ? nil : app.status.label {
                Text("Detector label \(label) · \(app.status.logFile)").font(.caption2.monospaced()).foregroundStyle(Palette.secondaryText)
            }
        }
    }

    private func tile(_ title: String, _ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) { Image(systemName: icon).foregroundStyle(Palette.accentSoft); Text(title).font(.subheadline.weight(.medium)) }
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }.buttonStyle(.plain).disabled(disabled || !app.link.controlsReady || busy != nil)
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if files.isEmpty {
                Button { run("Listing") { files = try await app.link.listFiles() } } label: {
                    Label(busy == "Listing" ? "Reading card…" : "List files", systemImage: "sdcard").frame(maxWidth: .infinity)
                }.buttonStyle(.glass).disabled(!app.link.controlsReady || busy != nil)
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
                            Text(f.name).font(.caption.monospaced()).lineLimit(1)
                            Text("\(f.size / 1024) KB · \(f.modified.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "arrow.down.circle").foregroundStyle(Palette.accentSoft)
                    }
                }.buttonStyle(.plain).disabled(busy != nil)
            }
            if busy == "Downloading" { ProgressView(progress).font(.caption) ; Button("Cancel", role: .cancel) { app.link.cancelCommand() } }
            if let download { ShareLink(item: download) { Label("Share \(download.lastPathComponent)", systemImage: "square.and.arrow.up") }.font(.footnote) }
            Text("Downloading a muon log also imports it into Runs, or fills the gaps of the matching phone run.").font(.caption).foregroundStyle(Palette.secondaryText)
        }.card()
    }

    @ViewBuilder private var expertLink: some View {
        if app.expertMode {
            NavigationLink { ExpertConsoleView() } label: {
                Label("Expert console", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, alignment: .leading)
            }.card()
        } else {
            HStack(spacing: 12) {
                Image(systemName: "lock").foregroundStyle(Palette.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expert console").font(.subheadline.weight(.medium))
                    Text("High voltage, thresholds and FPGA. Turn on Expert mode in Settings.").font(.caption).foregroundStyle(Palette.secondaryText)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(Palette.secondaryText.opacity(0.5)))
        }
    }
}
