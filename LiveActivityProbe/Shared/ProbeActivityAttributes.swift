import ActivityKit
import Foundation

/// Deliberately the simplest possible Live Activity payload — one Int, no
/// dates, no formatting, nothing that could itself be the bug. This file is
/// compiled into both the app and the widget extension (same pattern as
/// Sleep Timer's own SleepTimerActivityAttributes.swift), which is how
/// ActivityKit is designed to work across the process boundary.
struct ProbeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var tapCount: Int
    }
}
