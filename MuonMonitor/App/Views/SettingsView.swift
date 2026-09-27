import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Query private var runs: [Run]
    @State private var choosingFolder = false
    @AppStorage("liveActivity") private var liveActivity = true
    @State private var overdue = Alerts.overdueMinutes
    @State private var alertOn: [Alerts.Kind: Bool] = Dictionary(uniqueKeysWithValues: Alerts.Kind.allCases.map { ($0, Alerts.isEnabled($0)) })
    @State private var confirmForget = false
    @State private var savedAll: String?

    var body: some View {
        @Bindable var app = app
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $app.expertMode) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Expert mode")
                            Text("Shows high voltage, DAC thresholds, FPGA and raw counters").font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                    }
                }

                Section {
                    Button { choosingFolder = true } label: {
                        LabeledContent("Folder", value: app.cloud.folderName ?? "Choose…")
                    }
                    if app.cloud.isConfigured {
                        Button("Save all runs now") {
                            let ok = runs.filter { app.cloud.save($0) }.count
                            savedAll = "\(ok) of \(runs.count) runs saved."
                        }
                    }
                    if let p = app.cloud.problem { Label(p, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Palette.warning) }
                    if let savedAll { Text(savedAll).font(.footnote).foregroundStyle(Palette.secondaryText) }
                } header: { Text("Saving") } footer: {
                    Text("Pick iCloud Drive › cosmic. Each run is written to cosmic › phone › <date_name> as minutes.csv (raw counts, pressure, temperature and GPS for every minute) and run.json (name, tags, notes, events). Live runs save every 5 minutes and when logging stops. SD-card imports can come from anywhere in the folder, such as rawData.")
                }

                Section("Location") {
                    LabeledContent("Permission", value: app.location.permissionText)
                    if app.location.authorization == .authorizedWhenInUse {
                        Button("Allow in the background") { app.location.requestAlways() }
                    }
                    Text("Every minute stores the latest GPS fix, if it is less than 2 minutes old. The detector never receives or broadcasts your location.")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                }

                Section("Lock Screen") {
                    Toggle("Live Activity while logging", isOn: $liveActivity)
                    Button("Restart Live Activity") { app.restartLiveActivity() }.disabled(!app.logging)
                    Text("iOS ends a Live Activity after about 8 hours. Restart it here; logging continues either way.")
                        .font(.caption).foregroundStyle(Palette.secondaryText)
                }

                Section {
                    ForEach(Alerts.Kind.allCases, id: \.self) { k in
                        Toggle(k.title, isOn: Binding(get: { alertOn[k] ?? true }, set: { alertOn[k] = $0; Alerts.setEnabled(k, $0) }))
                    }
                    Stepper("Overdue after \(overdue) min", value: $overdue, in: 2...30).onChange(of: overdue) { _, v in Alerts.overdueMinutes = v }
                } header: { Text("Alerts") } footer: {
                    Text("Alerts are local notifications. Each kind is sent at most once every 30 minutes.")
                }

                Section("Widgets and Control Center") {
                    LabeledContent("Data sharing", value: SharedStore.isAvailable ? "On" : "Off")
                    if !SharedStore.isAvailable {
                        Text("Home Screen widgets and the Control Center toggle need the App Group capability. See the README; the Live Activity works without it.")
                            .font(.caption).foregroundStyle(Palette.secondaryText)
                    }
                }

                Section("Detector") {
                    Button("Forget MuonP4", role: .destructive) { confirmForget = true }.disabled(app.logging)
                }

                Section("About the data") {
                    Text("Counts are stored exactly as the detector reports them. No pressure or temperature correction is applied in the app: the detector compensates the SiPM bias for temperature itself, and pressure and temperature are stored with every minute for later analysis.")
                        .font(.footnote).foregroundStyle(Palette.secondaryText)
                    if app.demo { DemoBanner() }
                }
            }
            .navigationTitle("Settings")
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { app.cloud.choose(url) }
            }
            .confirmationDialog("Forget this detector?", isPresented: $confirmForget) {
                Button("Forget", role: .destructive) { app.link.forget() }
            } message: { Text("The next time you start logging, the app pairs with the first MuonP4 it finds.") }
        }
    }
}
