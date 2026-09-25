import Foundation

/// Abstraction for starting/updating/ending the Live Activity that mirrors
/// a running sleep timer, kept separate from `SleepTimerManager` for the
/// same reason `MediaPausing` is: the timer's own logic shouldn't know or
/// care whether Live Activities are supported, authorized, or even
/// compiled in for a given target — watchOS has no ActivityKit at all, and
/// tests substitute a spy that touches no system API.
protocol ActivityControlling {
    /// Starts a new Live Activity, or - if one from a previous process is
    /// still around (e.g. after a relaunch while a timer was running) -
    /// adopts and updates that one instead of creating a duplicate.
    func start(startDate: Date, endDate: Date)
    /// Reflects a new end date (e.g. from `addTime`) into the running
    /// Live Activity. A no-op if none is active.
    func update(endDate: Date)
    /// Ends and dismisses the Live Activity. A no-op if none is active.
    func end()
}

#if canImport(ActivityKit)
import ActivityKit

/// Every call here is best-effort: Live Activities can be turned off
/// system-wide or per-app in Settings, `Activity.request` can throw for
/// reasons outside our control, and none of that may ever prevent the
/// timer itself from starting, extending, or completing.
final class SleepTimerActivityController: ActivityControlling {
    private var activity: Activity<SleepTimerActivityAttributes>?
    private var startDate: Date?

    func start(startDate: Date, endDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        self.startDate = startDate
        let state = SleepTimerActivityAttributes.ContentState(startDate: startDate, endDate: endDate)
        let content = ActivityContent(state: state, staleDate: endDate)

        if let existing = Activity<SleepTimerActivityAttributes>.activities.first {
            // Reconnect to an activity that outlived a relaunch, rather
            // than dismissing and recreating it.
            activity = existing
            Task { await existing.update(content) }
            return
        }

        do {
            activity = try Activity.request(attributes: SleepTimerActivityAttributes(), content: content)
        } catch {
            activity = nil
        }
    }

    func update(endDate: Date) {
        guard let activity, let startDate else { return }
        let state = SleepTimerActivityAttributes.ContentState(startDate: startDate, endDate: endDate)
        let content = ActivityContent(state: state, staleDate: endDate)
        Task { await activity.update(content) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        self.startDate = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
#else
/// No-op stand-in on platforms without ActivityKit (watchOS), so
/// `SleepTimerManager`'s default initializer parameter compiles
/// identically everywhere this file is shared.
final class SleepTimerActivityController: ActivityControlling {
    func start(startDate: Date, endDate: Date) {}
    func update(endDate: Date) {}
    func end() {}
}
#endif
