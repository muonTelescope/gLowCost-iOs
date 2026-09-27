import Foundation
import WidgetKit

/// What the widgets and Control Center need, written by the app after every
/// minute. Stored in the App Group when one is configured (see README); without
/// it the widgets show a prompt to open the app.
struct WidgetSnapshot: Codable, Equatable {
    var logging: Bool
    var phase: Phase
    var runName: String
    var runStart: Date?
    var pairs: [Int]
    var recent: [Int]           // last 60 minute totals, -1 = no physics minute
    var meanRate: Double?
    var pressure: Double?
    var pressureChange3h: Double?
    var temperature: Double?
    var sampleDate: Date?
    var totalMuons: Int
    var exposureMinutes: Int

    var total: Int? { pairs.count == 3 ? pairs.reduce(0, +) : nil }
    static let empty = WidgetSnapshot(logging: false, phase: .stopped, runName: "", runStart: nil, pairs: [], recent: [], meanRate: nil,
                                      pressure: nil, pressureChange3h: nil, temperature: nil, sampleDate: nil, totalMuons: 0, exposureMinutes: 0)
    static let preview = WidgetSnapshot(logging: true, phase: .physics, runName: "External battery", runStart: Date().addingTimeInterval(-63_660),
                                        pairs: [23, 16, 21], recent: [57, 52, 60, 55, 61, 49, 58, 63, 54, 57, 60, 52, 59, 56, 62, 55, 58, 60, 53, 57, 61, 56, 59, 55, 57, 58, 54, 62, 57, 60],
                                        meanRate: 56.9, pressure: 982.3, pressureChange3h: -0.9, temperature: 24.0,
                                        sampleDate: Date().addingTimeInterval(-14), totalMuons: 60_348, exposureMinutes: 1_061)
}

enum SharedStore {
    /// App Group identifier from Info.plist (MuonAppGroup). Empty if the group was not set up.
    static var groupID: String? {
        let v = Bundle.main.object(forInfoDictionaryKey: "MuonAppGroup") as? String
        return (v?.isEmpty == false && v?.contains("$(") == false) ? v : nil
    }
    static var defaults: UserDefaults? {
        guard let groupID else { return nil }
        return UserDefaults(suiteName: groupID)
    }
    static var isAvailable: Bool {
        guard let groupID else { return false }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }
    /// Group copy for widgets; the app's own copy is used by Siri/Shortcuts when no group exists.
    static func load() -> WidgetSnapshot? {
        guard let d = defaults?.data(forKey: "snapshot") ?? UserDefaults.standard.data(forKey: "snapshot") else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }
    static func save(_ s: WidgetSnapshot, reload: Bool = true) {
        guard let d = try? JSONEncoder().encode(s) else { return }
        defaults?.set(d, forKey: "snapshot")
        UserDefaults.standard.set(d, forKey: "snapshot")
        if reload {
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        }
    }
}
