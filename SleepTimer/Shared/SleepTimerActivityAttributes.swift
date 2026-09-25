#if canImport(ActivityKit)
import ActivityKit
import Foundation

/// Static + dynamic content shared between the app and the Live Activity's
/// widget extension. Kept to just the two dates: the extension derives the
/// live countdown text and progress from them via system-rendered views
/// (`Text(timerInterval:)`, `ProgressView(timerInterval:)`), so there's
/// never a need to push a per-second update ourselves.
struct SleepTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startDate: Date
        var endDate: Date
    }
}
#endif
