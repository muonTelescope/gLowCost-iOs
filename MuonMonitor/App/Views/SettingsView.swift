import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings as chamfered cards (instead of a grouped Form) so it matches the rest of the app.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppHost.self) private var host
    @Query private var runs: [Run]
    @State private var choosingFolder = false
    @AppStorage("liveActivity") private var liveActivity = true
    @AppStorage("useSystemTabBar") private var useSystemTabBar = false
    @State private var overdue = SettingsView.nearestChoice(Alerts.overdueMinutes)
    @State private var alertOn: [Alerts.Kind: Bool] = Dictionary(uniqueKeysWithValues: Alerts.Kind.allCases.map { ($0, Alerts.isEnabled($0)) })
    @State private var confirmForget = false
    @State private var savedAll: String?

    /// Choices for "Alert when updates stop". The detector sends one minute per minute,
    /// so anything under 2 min would fire on ordinary Bluetooth hiccups.
    static let overdueChoices = [2, 3, 5, 10, 15, 30]
    static func nearestChoice(_ m: Int) -> Int { overdueChoices.min { abs($0 - m) < abs($1 - m) } ?? 3 }

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 1).id(TabScrollTop.anchor(.settings)).accessibilityHidden(true)
                    if app.demo { demoCard }

                    SectionLabel("Mode")
                    VStack(spacing: 0) {
                        toggleRow("Expert mode", detail: "High voltage, DAC thresholds, FPGA and raw counters", isOn: $app.expertMode)
                    }.card(padding: 0)

                    SectionLabel("Saving")
                    VStack(alignment: .leading, spacing: 0) {
                        Button { choosingFolder = true } label: {
                            row("Folder") { Text(app.cloud.folderName ?? "Choose…").font(Typography.monoBody).foregroundStyle(Palette.lilac) }
                        }.buttonStyle(.plain)
                        if app.cloud.isConfigured {
                            RowDivider()
                            Button {
                                let ok = runs.filter { app.cloud.save($0) }.count
                                savedAll = "\(ok) of \(runs.count) runs saved."
                            } label: { row("Save all runs now") { Image(systemName: "icloud.and.arrow.up").foregroundStyle(Palette.lilac) } }
                                .buttonStyle(.plain)
                        }
                        if let p = app.cloud.problem {
                            Label(p, systemImage: "exclamationmark.triangle").font(Typography.footnote).foregroundStyle(Palette.alert).padding(14)
                        }
                        if let savedAll { Text(savedAll).font(Typography.footnote).foregroundStyle(Palette.secondaryText).padding(.horizontal, 14).padding(.bottom, 12) }
                    }.card(padding: 0)
                    footnote("Pick iCloud Drive › cosmic. Each run is written to cosmic › phone › <date_name> as minutes.csv (raw counts, pressure, temperature and GPS for every minute) and run.json (name, tags, notes, events). Live runs save every 5 minutes and when logging stops.")

                    SectionLabel("Location")
                    VStack(spacing: 0) {
                        row("Permission") { Text(app.location.permissionText).font(Typography.footnote).foregroundStyle(Palette.secondaryText) }
                        if app.location.authorization == .authorizedWhenInUse {
                            RowDivider()
                            Button { app.location.requestAlways() } label: { row("Allow in the background") { Image(systemName: "location").foregroundStyle(Palette.lilac) } }
                                .buttonStyle(.plain)
                        }
                    }.card(padding: 0)
                    footnote("Every minute stores the latest GPS fix if it is less than 2 minutes old. Available GPS fixes sync to the detector’s SD card while connected; missing locations can be assigned manually in Runs.")

                    SectionLabel("Lock Screen")
                    VStack(spacing: 0) {
                        toggleRow("Live Activity while logging", isOn: $liveActivity)
                        RowDivider()
                        Button { app.restartLiveActivity() } label: { row("Restart Live Activity") { Image(systemName: "arrow.clockwise").foregroundStyle(Palette.lilac) } }
                            .buttonStyle(.plain).disabled(!app.logging)
                    }.card(padding: 0)
                    footnote("iOS ends a Live Activity after about 8 hours. Restart it here; logging continues either way.")

                    SectionLabel("Alerts")
                    VStack(spacing: 0) {
                        row("Alert when updates stop") {
                            Picker("After", selection: $overdue) {
                                ForEach(Self.overdueChoices, id: \.self) { Text("After \($0) min").tag($0) }
                            }
                            .pickerStyle(.menu).tint(Palette.lilac).labelsHidden()
                            .disabled(!(alertOn[.overdue] ?? true))
                        }
                        ForEach(Alerts.Kind.allCases, id: \.self) { k in
                            RowDivider()
                            toggleRow(k.title, isOn: Binding(get: { alertOn[k] ?? true }, set: { alertOn[k] = $0; Alerts.setEnabled(k, $0) }))
                        }
                    }.card(padding: 0)
                    .onChange(of: overdue) { _, v in
                        Alerts.overdueMinutes = v
                        if app.logging, let end = app.lastMinuteEnd { Alerts.armOverdue(lastSample: end) }   // re-arm with the new delay
                    }
                    footnote("Local notifications only. Each kind is sent at most once every 30 minutes. The overdue alert fires even while the phone is locked.")

                    SectionLabel("Widgets and Control Center")
                    VStack(alignment: .leading, spacing: 0) {
                        row("Data sharing") { Text(SharedStore.isAvailable ? "On" : "Off").font(Typography.monoBody).foregroundStyle(SharedStore.isAvailable ? Palette.physics : Palette.secondaryText) }
                        if !SharedStore.isAvailable {
                            Text("Home Screen widgets and the Control Center toggle need the App Group capability (see the README). The Live Activity works without it.")
                                .font(Typography.caption).foregroundStyle(Palette.secondaryText).padding(.horizontal, 14).padding(.bottom, 12)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }.card(padding: 0)

                    SectionLabel("About the data")
                    Text("Counts are stored exactly as the detector reports them. No pressure or temperature correction is applied: the detector compensates the SiPM bias for temperature itself, and pressure and temperature are stored with every minute for later analysis.")
                        .font(Typography.footnote).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
                        .card()

                    #if DEBUG
                    SectionLabel("Debug")
                    VStack(spacing: 0) {
                        toggleRow("Use system tab bar", detail: "Apple's Liquid Glass tab bar instead of the chamfered one", isOn: $useSystemTabBar)
                    }.card(padding: 0)
                    #endif

                    Button("Forget MuonP4", role: .destructive) { confirmForget = true }
                        .buttonStyle(.muonDestructive).disabled(app.logging || app.demo)
                        .padding(.top, 6)
                }
                // Review fix 7: content ends right after the last card.
                .padding(.horizontal, 20).padding(.bottom, 8)
            }
            .tabScrollTop(.settings)
            .background(Palette.background)
            .navigationTitle("Settings")
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { app.cloud.choose(url) }
            }
            .confirmationDialog("Forget this detector?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget", role: .destructive) { app.link.forget() }
            } message: { Text("The next time you start logging, the app pairs with the first MuonP4 it finds.") }
        }
    }

    private var demoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            DemoBanner()
            Text("You are exploring generated data. Nothing is saved and no detector is used.")
                .font(Typography.footnote).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true)
            Button("Leave the demo") { host.exitDemo() }.buttonStyle(.muonPrimary)
        }.card(edge: .bright)
    }

    private func row<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Text(title).font(Typography.body).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func toggleRow(_ title: String, detail: String? = nil, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.body).foregroundStyle(Palette.ink)
                if let detail { Text(detail).font(Typography.caption).foregroundStyle(Palette.secondaryText).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .tint(Palette.violet)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func footnote(_ s: String) -> some View {
        Text(s).font(Typography.caption).foregroundStyle(Palette.secondaryText)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
    }
}
