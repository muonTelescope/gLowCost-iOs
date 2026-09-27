import AppIntents

struct StartLoggingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Muon Logging"
    static let description = IntentDescription("Connects to your MuonP4 and starts recording every minute on this iPhone.")
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await IntentActions.setLogging?(true)
        return .result(dialog: "Logging started. The first minute arrives within about a minute.")
    }
}

struct MuonRateIntent: AppIntent {
    static let title: LocalizedStringResource = "Muon Rate"
    static let description = IntentDescription("The number of coincidences in the detector's last completed minute.")
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let s = SharedStore.load(), let total = s.total, let date = s.sampleDate else {
            return .result(value: 0, dialog: "No minute has been received yet. Start logging near your detector.")
        }
        let age = Int(Date().timeIntervalSince(date) / 60)
        let when = age < 2 ? "In the last minute" : "In the minute ending \(age) minutes ago"
        return .result(value: total, dialog: "\(when), your detector counted \(total) muon coincidences.")
    }
}

struct MuonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: MuonRateIntent(), phrases: ["What's the muon rate in \(.applicationName)", "How many muons in \(.applicationName)"],
                    shortTitle: "Muon rate", systemImageName: "chart.bar.fill")
        AppShortcut(intent: StartLoggingIntent(), phrases: ["Start logging in \(.applicationName)"],
                    shortTitle: "Start logging", systemImageName: "record.circle")
        AppShortcut(intent: StopLoggingIntent(), phrases: ["Stop logging in \(.applicationName)"],
                    shortTitle: "Stop logging", systemImageName: "stop.circle")
    }
}
