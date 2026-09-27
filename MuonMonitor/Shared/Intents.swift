import AppIntents
import ActivityKit
import Foundation

/// The app registers its handlers here at launch. Intents compiled into the
/// widget extension run in the app's process (LiveActivityIntent, or when iOS
/// launches the app in the background), so the handlers are present when needed.
@MainActor
enum IntentActions {
    static var setLogging: (@MainActor (Bool) async -> Void)?
    static var startPhysicsRun: (@MainActor () async throws -> Void)?
}

/// Stop button on the Live Activity and Dynamic Island.
struct StopLoggingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Muon Logging"
    static let description = IntentDescription("Stops logging from MuonP4 on this iPhone. The detector keeps counting to its SD card.")
    func perform() async throws -> some IntentResult {
        await IntentActions.setLogging?(false)
        return .result()
    }
}

/// Control Center / Shortcuts toggle.
struct SetLoggingIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Muon Logging"
    static let description = IntentDescription("Starts or stops logging from your MuonP4 detector.")
    /// Opens the app so Bluetooth runs in the app's process, not the widget extension.
    static let openAppWhenRun = true
    @Parameter(title: "Logging") var value: Bool
    init() {}
    init(_ on: Bool) { value = on }
    func perform() async throws -> some IntentResult {
        await IntentActions.setLogging?(value)
        return .result()
    }
}

/// Opens the app so the encrypted command can be sent over an active connection.
struct StartPhysicsRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Physics Run"
    static let description = IntentDescription("Turns the detector's Wi‑Fi off, cycles high voltage and starts clean physics counting.")
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult {
        try await IntentActions.startPhysicsRun?()
        return .result()
    }
}
