#if canImport(ActivityKit)
import AppIntents

/// Live Activity button intents. Conforming to `LiveActivityIntent` (rather
/// than plain `AppIntent`) is what makes the system run `perform()` in the
/// app's own process when the person taps a button on the Lock Screen or in
/// the Dynamic Island, instead of the widget extension's — which is exactly
/// what lets these call straight into the same `SleepTimerManager` the rest
/// of the app uses, through the same `addTime`/`cancel`, writing the same
/// absolute `endDate`. There is no second timer implementation here: these
/// are just another caller of the existing one, the same as the +5 min,
/// Custom, and Cancel buttons in RunningView.
struct AddFiveMinutesLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 5 Minutes"

    @MainActor
    func perform() async throws -> some IntentResult {
        SleepTimerManager.shared.addTime(5 * 60)
        return .result()
    }
}

struct AddTenMinutesLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Add 10 Minutes"

    @MainActor
    func perform() async throws -> some IntentResult {
        SleepTimerManager.shared.addTime(10 * 60)
        return .result()
    }
}

struct CancelSleepTimerLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Cancel Sleep Timer"

    @MainActor
    func perform() async throws -> some IntentResult {
        SleepTimerManager.shared.cancel()
        return .result()
    }
}
#endif
