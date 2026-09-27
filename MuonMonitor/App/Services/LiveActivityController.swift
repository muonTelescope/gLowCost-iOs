import Foundation
import ActivityKit

/// Local (no-push) Live Activity: works with a free developer account.
@MainActor
final class LiveActivityController {
    private var activity: Activity<MuonActivity>?
    private var lastState: MuonActivity.ContentState?

    init() { activity = Activity<MuonActivity>.activities.first }

    var enabledInSettings: Bool { UserDefaults.standard.object(forKey: "liveActivity") as? Bool ?? true }
    var systemAllows: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(_ state: MuonActivity.ContentState) throws {
        guard enabledInSettings, systemAllows else { return }
        if let activity, activity.activityState == .active { update(state); return }
        activity = try Activity.request(attributes: MuonActivity(), content: ActivityContent(state: state, staleDate: stale(for: state)), pushType: nil)
        lastState = state
    }

    func update(_ state: MuonActivity.ContentState) {
        guard let activity, state != lastState else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: stale(for: state))
        Task { await activity.update(content) }
    }

    func restart(_ state: MuonActivity.ContentState) throws {
        let old = activity; activity = nil; lastState = nil
        if let old { Task { await old.end(nil, dismissalPolicy: .immediate) } }
        try start(state)
    }

    func end() {
        let old = activity; activity = nil; lastState = nil
        if let old { Task { await old.end(nil, dismissalPolicy: .immediate) } }
    }

    /// iOS marks the activity stale when no minute arrives within the overdue window.
    private func stale(for s: MuonActivity.ContentState) -> Date {
        (s.sampleDate ?? Date()).addingTimeInterval(Double(Alerts.overdueMinutes * 60) + 60)
    }
}
