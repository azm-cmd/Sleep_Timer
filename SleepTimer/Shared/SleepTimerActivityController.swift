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
    /// Why the most recent `start()` didn't result in a visible Live
    /// Activity, if it didn't - nil on success. Surfaced in RunningView so
    /// this is diagnosable from the device alone: sideloaded installs have
    /// no Xcode session and no Mac to read Console.app from, so a silently
    /// swallowed `Activity.request` failure would otherwise be invisible.
    var lastFailureReason: String? { get }
}

#if canImport(ActivityKit)
import ActivityKit
import os

/// Every call here is best-effort: Live Activities can be turned off
/// system-wide or per-app in Settings, `Activity.request` can throw for
/// reasons outside our control, and none of that may ever prevent the
/// timer itself from starting, extending, or completing. Every one of
/// those "give up silently" paths also logs why, via the unified logging
/// system — visible in Console.app on the device with no Xcode session
/// attached, which matters here specifically because this controller has
/// never been exercised on a real device or through a sideloaded install
/// in this project's history; if Live Activities silently fail there,
/// this is the only way to see why without guessing.
private let activityLog = Logger(subsystem: "com.azm.sleeptimer", category: "LiveActivity")

final class SleepTimerActivityController: ActivityControlling {
    private var activity: Activity<SleepTimerActivityAttributes>?
    private var startDate: Date?
    private(set) var lastFailureReason: String?

    func start(startDate: Date, endDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastFailureReason = "Live Activities are disabled (Settings > Face ID & Passcode > Allow Access When Locked, or Settings > Sleep Timer)."
            activityLog.notice("start(): areActivitiesEnabled is false — skipping. Check Settings > [App] > Live Activities, and Settings > Face ID & Passcode > Allow Access When Locked > Live Activities.")
            return
        }
        lastFailureReason = nil
        self.startDate = startDate
        let state = SleepTimerActivityAttributes.ContentState(startDate: startDate, endDate: endDate)
        let content = ActivityContent(state: state, staleDate: endDate)

        if let existing = Activity<SleepTimerActivityAttributes>.activities.first {
            // Reconnect to an activity that outlived a relaunch, rather
            // than dismissing and recreating it.
            activity = existing
            activityLog.notice("start(): reconnected to an existing Activity (id: \(existing.id, privacy: .public)) rather than creating a new one.")
            Task { await existing.update(content) }
            return
        }

        do {
            activity = try Activity.request(attributes: SleepTimerActivityAttributes(), content: content)
            activityLog.notice("start(): Activity.request succeeded (id: \(self.activity?.id ?? "?", privacy: .public)).")
        } catch {
            activity = nil
            let description = String(describing: error)
            lastFailureReason = description
            activityLog.error("start(): Activity.request threw and was swallowed — this is why nothing appears on-screen: \(description, privacy: .public)")
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
    var lastFailureReason: String? { nil }
    func start(startDate: Date, endDate: Date) {}
    func update(endDate: Date) {}
    func end() {}
}
#endif
