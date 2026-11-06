import Foundation
import Combine
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Owns the active sleep timer's state and is the single source of truth for
/// both the iPhone and Watch apps.
///
/// The timer is never driven by decrementing a counter. `start`/`addTime`
/// only ever write an absolute `endDate`; every view reads `remaining` and
/// `progress`, which are recomputed from that end date and the current time
/// on every tick. This is what makes the countdown correct after the app is
/// backgrounded, the screen locks, or the process is relaunched.
///
/// **Why the 1-second `ticker` can now actually fire while backgrounded:**
/// a plain app with no active background mode is suspended shortly after
/// being backgrounded — zero CPU time, so the ticker would simply stop,
/// and neither it nor the pause inside `complete()` could run again until
/// the app was next foregrounded (investigated at length in README.md
/// under "Background execution: what's actually possible" — BGTaskScheduler
/// is opportunistic and not time-precise, and a local notification doesn't
/// hand the app any execution time of its own). `start`/`addTime` now call
/// `mediaController.beginBackgroundKeepAlive()`, which keeps a genuinely
/// active (silent, mixing) `AVAudioSession` running for exactly as long as
/// a timer is active — the same `audio` background-mode exemption a
/// podcast app relies on to keep decoding in the background, which keeps
/// this process's *entire* run loop alive, not just audio code. That mode
/// was avoided earlier purely over an App Store review-policy risk
/// (Guideline 2.5.4); since this app is sideloaded and never submitted for
/// review, that risk doesn't apply, and the OS mechanism itself is
/// unchanged either way. If the keep-alive ever fails to start (Live
/// Activities-style best-effort — see `MediaController`), every expiry
/// path (`tick`'s `checkForExpiry`, and `refreshFromPersistence`/`init`'s
/// `syncAfterRestoringState`) still funnels through the same `complete()`,
/// so the pause and the finished state are still always caught up exactly
/// once, as soon as the app is next foregrounded, the same fallback this
/// relied on before the keep-alive existed.
@MainActor
final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    @Published private(set) var state: SleepTimerState?
    @Published private(set) var now: Date = Date()
    /// True from the moment the timer naturally completes until the person
    /// acknowledges the finished screen (or starts a new timer). Never set
    /// by `cancel()` — cancelling is a deliberate user action, not completion.
    @Published private(set) var didFinish = false
    /// Why the Live Activity didn't appear for the current timer, if it
    /// didn't - nil once one is showing (or on platforms without
    /// ActivityKit, where it's always nil). Read from `activityController`
    /// right after every `start()` call, since a sideloaded install has no
    /// way to read Console.app to find this out otherwise.
    @Published private(set) var liveActivityDiagnostic: String?

    private let defaults: UserDefaults
    private let mediaController: MediaPausing
    private let activityController: ActivityControlling
    private let stateKey = "com.azm.sleeptimer.activeState"
    private let notificationID = "com.azm.sleeptimer.completion"
    private var ticker: AnyCancellable?

    init(
        defaults: UserDefaults = .standard,
        mediaController: MediaPausing = MediaController(),
        activityController: ActivityControlling = SleepTimerActivityController()
    ) {
        self.defaults = defaults
        self.mediaController = mediaController
        self.activityController = activityController
        restoreState()
        // Catches the case where the process was fully relaunched (not just
        // foregrounded) after the timer's end date already passed while
        // backgrounded — e.g. the app was terminated overnight. Without
        // this, a cold launch would silently discard the expired state
        // without ever attempting the pause or showing the finished screen.
        // For a still-running timer, this is also what reconnects the Live
        // Activity after a relaunch.
        syncAfterRestoringState(at: Date())
        ticker = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.tick(at: date)
            }
    }

    var isRunning: Bool { state != nil }

    var remaining: TimeInterval {
        state?.remaining(asOf: now) ?? 0
    }

    var progress: Double {
        state?.progress(asOf: now) ?? 0
    }

    func start(duration: TimeInterval) {
        let start = Date()
        let end = start.addingTimeInterval(duration)
        state = SleepTimerState(startDate: start, endDate: end)
        now = start
        didFinish = false
        persist()
        scheduleCompletionNotification()
        activityController.start(startDate: start, endDate: end)
        liveActivityDiagnostic = activityController.lastFailureReason
        mediaController.beginBackgroundKeepAlive()
    }

    func addTime(_ interval: TimeInterval) {
        guard var current = state else { return }
        current.endDate = current.endDate.addingTimeInterval(interval)
        state = current
        persist()
        scheduleCompletionNotification()
        activityController.update(endDate: current.endDate)
    }

    func cancel() {
        state = nil
        persist()
        cancelCompletionNotification()
        activityController.end()
        liveActivityDiagnostic = nil
        mediaController.endBackgroundKeepAlive()
    }

    /// Call once the person has seen the "finished" screen (or is starting
    /// a new timer) to return to the normal setup state.
    func acknowledgeFinished() {
        didFinish = false
    }

    /// Call when the app becomes active again (foreground / relaunch) to
    /// re-derive remaining time from persisted state rather than trusting
    /// whatever was last held in memory.
    func refreshFromPersistence() {
        restoreState()
        now = Date()
        syncAfterRestoringState(at: now)
    }

    private func tick(at date: Date) {
        now = date
        checkForExpiry(at: date)
    }

    /// The single place a live timer is recognized as having reached zero,
    /// whether that's discovered by the live per-second tick, by the app
    /// reactivating after being backgrounded, or by a cold relaunch after
    /// the end date already passed. Every one of those paths funnels
    /// through `complete()`, so the pause attempt and the finished-state
    /// flag each fire exactly once per completed timer.
    private func checkForExpiry(at date: Date) {
        if let state, state.isExpired(asOf: date) {
            complete()
        }
    }

    /// Called right after `restoreState()` (app launch or reactivation).
    /// Either completes a timer whose end date already passed, or - for one
    /// still running - makes sure the Live Activity is showing and current,
    /// and the background keep-alive is (re-)running, since both are
    /// per-process runtime state that a relaunch (not just a reactivation)
    /// loses entirely.
    private func syncAfterRestoringState(at date: Date) {
        guard let state else { return }
        if state.isExpired(asOf: date) {
            complete()
        } else {
            activityController.start(startDate: state.startDate, endDate: state.endDate)
            liveActivityDiagnostic = activityController.lastFailureReason
            mediaController.beginBackgroundKeepAlive()
        }
    }

    private func complete() {
        state = nil
        persist()
        cancelCompletionNotification()
        mediaController.pauseCurrentMedia()
        activityController.end()
        liveActivityDiagnostic = nil
        didFinish = true
    }

    private func restoreState() {
        guard let data = defaults.data(forKey: stateKey),
              let decoded = try? JSONDecoder().decode(SleepTimerState.self, from: data) else {
            state = nil
            return
        }
        state = decoded
    }

    private func persist() {
        guard let state else {
            defaults.removeObject(forKey: stateKey)
            return
        }
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }

    private func scheduleCompletionNotification() {
        #if canImport(UserNotifications)
        guard let state else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        let content = UNMutableNotificationContent()
        content.title = "Sleep Timer"
        content.body = "Your sleep timer has ended."
        content.sound = .default

        let interval = max(1, state.remaining())
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        center.add(request)
        #endif
    }

    private func cancelCompletionNotification() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        #endif
    }
}
