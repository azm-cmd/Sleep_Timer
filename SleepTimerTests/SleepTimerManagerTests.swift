import XCTest
@testable import SleepTimer

/// Records how many times a pause was requested, without touching any real
/// audio session — lets timer-completion behavior be tested without a
/// device, media session, or anything actually playing.
final class SpyMediaController: MediaPausing {
    private(set) var pauseCount = 0

    func pauseCurrentMedia() {
        pauseCount += 1
    }
}

@MainActor
final class SleepTimerManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var mediaController: SpyMediaController!
    private var manager: SleepTimerManager!
    private let suiteName = "SleepTimerManagerTests"
    private let stateKey = "com.azm.sleeptimer.activeState"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        mediaController = SpyMediaController()
        manager = SleepTimerManager(defaults: defaults, mediaController: mediaController)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        manager = nil
        mediaController = nil
        defaults = nil
        super.tearDown()
    }

    // MARK: - Existing timer behavior

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
        let relaunched = SleepTimerManager(defaults: defaults, mediaController: SpyMediaController())
        XCTAssertTrue(relaunched.isRunning)
        XCTAssertEqual(relaunched.remaining, 600, accuracy: 1.0)
    }

    func testRefreshFromPersistenceRecomputesRemaining() {
        manager.start(duration: 600)
        rewritePersistedEndDate(to: Date().addingTimeInterval(120))
        manager.refreshFromPersistence()
        XCTAssertEqual(manager.remaining, 120, accuracy: 1.0)
    }

    // MARK: - Completion: media pause + "finished" state

    /// Timer completes with no media abstraction available beyond the spy —
    /// completion must still succeed and finish normally.
    func testTimerCompletesWithNoMediaPlaying() {
        manager.start(duration: 600)
        rewritePersistedEndDate(to: Date().addingTimeInterval(-1))

        manager.refreshFromPersistence()

        XCTAssertFalse(manager.isRunning)
        XCTAssertTrue(manager.didFinish)
    }

    /// Timer completes with the media-control abstraction available: the
    /// pause attempt is made.
    func testTimerCompletionAttemptsPauseThroughMediaController() {
        manager.start(duration: 600)
        rewritePersistedEndDate(to: Date().addingTimeInterval(-1))

        manager.refreshFromPersistence()

        XCTAssertEqual(mediaController.pauseCount, 1)
    }

    /// A cold relaunch (not just reactivation) after the end date already
    /// passed while backgrounded must also route through completion, since
    /// `restoreState()` no longer special-cases expiry inline.
    func testColdRelaunchAfterExpiryCompletesAndPausesExactlyOnce() {
        let past = SleepTimerState(
            startDate: Date().addingTimeInterval(-120),
            endDate: Date().addingTimeInterval(-60)
        )
        if let data = try? JSONEncoder().encode(past) {
            defaults.set(data, forKey: stateKey)
        }

        let spy = SpyMediaController()
        let relaunched = SleepTimerManager(defaults: defaults, mediaController: spy)

        XCTAssertFalse(relaunched.isRunning)
        XCTAssertTrue(relaunched.didFinish)
        XCTAssertEqual(spy.pauseCount, 1)
    }

    func testCancellationDoesNotTriggerPause() {
        manager.start(duration: 600)
        manager.cancel()

        XCTAssertEqual(mediaController.pauseCount, 0)
        XCTAssertFalse(manager.didFinish)
    }

    func testAddingTimeDoesNotTriggerPauseEarly() {
        manager.start(duration: 600)
        manager.addTime(300)

        XCTAssertEqual(mediaController.pauseCount, 0)
        XCTAssertFalse(manager.didFinish)
    }

    /// Reactivating before the end date has passed must not treat the timer
    /// as complete.
    func testRefreshingBeforeExpiryDoesNotTriggerPause() {
        manager.start(duration: 600)
        manager.refreshFromPersistence()

        XCTAssertEqual(mediaController.pauseCount, 0)
        XCTAssertFalse(manager.didFinish)
    }

    /// Completion must trigger the pause exactly once even if the app is
    /// reactivated again afterward (state is already nil by then, so
    /// `checkForExpiry` has nothing left to act on).
    func testReactivatingAgainAfterCompletionDoesNotPauseTwice() {
        manager.start(duration: 600)
        rewritePersistedEndDate(to: Date().addingTimeInterval(-1))
        manager.refreshFromPersistence()
        manager.refreshFromPersistence()

        XCTAssertEqual(mediaController.pauseCount, 1)
    }

    func testAcknowledgeFinishedClearsFlagWithoutAnotherPauseAttempt() {
        manager.start(duration: 600)
        rewritePersistedEndDate(to: Date().addingTimeInterval(-1))
        manager.refreshFromPersistence()

        manager.acknowledgeFinished()

        XCTAssertFalse(manager.didFinish)
        XCTAssertEqual(mediaController.pauseCount, 1)
    }

    func testStartingANewTimerClearsAPreviousFinishedFlag() {
        manager.start(duration: 600)
        rewritePersistedEndDate(to: Date().addingTimeInterval(-1))
        manager.refreshFromPersistence()
        XCTAssertTrue(manager.didFinish)

        manager.start(duration: 300)

        XCTAssertFalse(manager.didFinish)
    }

    // MARK: - Helpers

    /// Rewrites the currently-persisted state's end date, simulating time
    /// having passed (or the timer having already elapsed) while the app
    /// wasn't actively ticking — the same situation backgrounding produces.
    private func rewritePersistedEndDate(to newEndDate: Date) {
        guard let data = defaults.data(forKey: stateKey),
              var state = try? JSONDecoder().decode(SleepTimerState.self, from: data) else {
            XCTFail("Expected persisted state to rewrite")
            return
        }
        state.endDate = newEndDate
        if let encoded = try? JSONEncoder().encode(state) {
            defaults.set(encoded, forKey: stateKey)
        }
    }
}
