import XCTest
@testable import SleepTimer

@MainActor
final class SleepTimerManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: SleepTimerManager!
    private let suiteName = "SleepTimerManagerTests"
    private let stateKey = "com.azm.sleeptimer.activeState"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        manager = SleepTimerManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        manager = nil
        defaults = nil
        super.tearDown()
    }

    func testStartSetsRemainingToDuration() {
        manager.start(duration: 600)
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(manager.remaining, 600, accuracy: 1.0)
    }

    func testAddTimeExtendsRemaining() {
        manager.start(duration: 600)
        manager.addTime(300)
        XCTAssertEqual(manager.remaining, 900, accuracy: 1.0)
    }

    func testAddTimeWithNoActiveTimerIsANoOp() {
        manager.addTime(300)
        XCTAssertFalse(manager.isRunning)
    }

    func testCancelClearsState() {
        manager.start(duration: 600)
        manager.cancel()
        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.remaining, 0)
    }

    /// Verifies the core requirement: remaining time is derived from an
    /// absolute end date, so a freshly constructed manager (simulating an
    /// app relaunch) reconstructs the correct remaining duration.
    func testStateSurvivesReconstructionFromPersistence() {
        manager.start(duration: 600)
        let relaunched = SleepTimerManager(defaults: defaults)
        XCTAssertTrue(relaunched.isRunning)
        XCTAssertEqual(relaunched.remaining, 600, accuracy: 1.0)
    }

    func testAlreadyExpiredPersistedStateIsNotRestored() {
        let past = SleepTimerState(
            startDate: Date().addingTimeInterval(-120),
            endDate: Date().addingTimeInterval(-60)
        )
        if let data = try? JSONEncoder().encode(past) {
            defaults.set(data, forKey: stateKey)
        }
        let relaunched = SleepTimerManager(defaults: defaults)
        XCTAssertFalse(relaunched.isRunning)
    }

    func testRefreshFromPersistenceRecomputesRemaining() {
        manager.start(duration: 600)
        // Simulate time passing while backgrounded by rewriting persisted
        // state to one that started earlier, then asking the manager to
        // recompute from that absolute end date.
        var state = SleepTimerState(startDate: Date(), endDate: Date())
        if let data = defaults.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(SleepTimerState.self, from: data) {
            state = decoded
        }
        state.endDate = Date().addingTimeInterval(120)
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }

        manager.refreshFromPersistence()
        XCTAssertEqual(manager.remaining, 120, accuracy: 1.0)
    }
}
