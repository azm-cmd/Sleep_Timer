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
@MainActor
final class SleepTimerManager: ObservableObject {
    static let shared = SleepTimerManager()

    @Published private(set) var state: SleepTimerState?
    @Published private(set) var now: Date = Date()
    /// True from the moment the timer naturally completes until the person
    /// acknowledges the finished screen (or starts a new timer). Never set
    /// by `cancel()` — cancelling is a deliberate user action, not completion.
    @Published private(set) var didFinish = false

    private let defaults: UserDefaults
    private let mediaController: MediaPausing
    private let stateKey = "com.azm.sleeptimer.activeState"
    private let notificationID = "com.azm.sleeptimer.completion"
    private var ticker: AnyCancellable?

    init(defaults: UserDefaults = .standard, mediaController: MediaPausing = MediaController()) {
        self.defaults = defaults
        self.mediaController = mediaController
        restoreState()
        // Catches the case where the process was fully relaunched (not just
        // foregrounded) after the timer's end date already passed while
        // backgrounded — e.g. the app was terminated overnight. Without
        // this, a cold launch would silently discard the expired state
        // without ever attempting the pause or showing the finished screen.
        checkForExpiry(at: Date())
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
        state = SleepTimerState(startDate: start, endDate: start.addingTimeInterval(duration))
        now = start
        didFinish = false
        persist()
        scheduleCompletionNotification()
    }

    func addTime(_ interval: TimeInterval) {
        guard var current = state else { return }
        current.endDate = current.endDate.addingTimeInterval(interval)
        state = current
        persist()
        scheduleCompletionNotification()
    }

    func cancel() {
        state = nil
        persist()
        cancelCompletionNotification()
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
        checkForExpiry(at: now)
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

    private func complete() {
        state = nil
        persist()
        cancelCompletionNotification()
        mediaController.pauseCurrentMedia()
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
