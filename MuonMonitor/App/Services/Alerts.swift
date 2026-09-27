import Foundation
import UserNotifications

/// Local notifications only (no push, no server), so they work on a free
/// developer account and while the phone is locked.
enum Alerts {
    enum Kind: String, CaseIterable {
        case overdue, stuckZero, jump, sdProblem, health
        var title: String {
            switch self {
            case .overdue: "MuonP4 stopped updating"
            case .stuckZero: "No coincidences"
            case .jump: "Sudden rate change"
            case .sdProblem: "SD card problem"
            case .health: "Counts look noisy"
            }
        }
        var defaultsKey: String { "alert.\(rawValue)" }
    }

    static func isEnabled(_ k: Kind) -> Bool { UserDefaults.standard.object(forKey: k.defaultsKey) as? Bool ?? true }
    static func setEnabled(_ k: Kind, _ on: Bool) { UserDefaults.standard.set(on, forKey: k.defaultsKey) }
    static var overdueMinutes: Int {
        get { max(2, UserDefaults.standard.integer(forKey: "alert.overdueMinutes") == 0 ? 3 : UserDefaults.standard.integer(forKey: "alert.overdueMinutes")) }
        set { UserDefaults.standard.set(newValue, forKey: "alert.overdueMinutes") }
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Re-armed after every sample: fires only if no further minute arrives in time,
    /// even when iOS has suspended the app.
    static func armOverdue(lastSample: Date) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: [Kind.overdue.rawValue])
        guard isEnabled(.overdue) else { return }
        let content = UNMutableNotificationContent()
        content.title = Kind.overdue.title
        content.body = "No new minute for \(overdueMinutes) minutes. The detector may be out of range or off. It keeps logging to its SD card if powered."
        content.sound = .default
        let delay = max(60, lastSample.addingTimeInterval(Double(overdueMinutes * 60) + 60).timeIntervalSinceNow)
        c.add(UNNotificationRequest(identifier: Kind.overdue.rawValue, content: content,
                                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
    }

    static func cancelOverdue() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Kind.overdue.rawValue])
    }

    /// Immediate alert, at most once per 30 minutes per kind.
    static func post(_ k: Kind, _ body: String) {
        guard isEnabled(k) else { return }
        let key = "alert.last.\(k.rawValue)"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last > 1800 else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
        let content = UNMutableNotificationContent()
        content.title = k.title; content.body = body; content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(k.rawValue).\(UUID().uuidString)", content: content, trigger: nil))
    }
}
