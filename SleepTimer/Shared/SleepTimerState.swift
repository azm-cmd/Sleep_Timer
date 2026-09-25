import Foundation

/// The durable, absolute-time record of a running sleep timer.
///
/// Remaining time is always derived from `endDate`, never from a decrementing
/// counter, so the timer stays correct across backgrounding, locking, and relaunch.
struct SleepTimerState: Codable, Equatable {
    var startDate: Date
    var endDate: Date

    var totalDuration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    func remaining(asOf now: Date = Date()) -> TimeInterval {
        max(0, endDate.timeIntervalSince(now))
    }

    /// 0 at the moment the timer started, 1 once it has fully elapsed.
    func progress(asOf now: Date = Date()) -> Double {
        let total = totalDuration
        guard total > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(startDate)
        return min(1, max(0, elapsed / total))
    }

    func isExpired(asOf now: Date = Date()) -> Bool {
        now >= endDate
    }
}
