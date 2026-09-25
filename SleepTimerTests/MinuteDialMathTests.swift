import XCTest
@testable import SleepTimer

/// Exercises `MinuteDialMath` directly against the exact interaction
/// sequences called out when the old ScrollView-based dial produced random
/// backward jumps: start at 30, nudge higher, nudge lower, several
/// consecutive movements in the same direction, reverse direction, a preset
/// changing the base, and interacting again after that. Every case here is
/// pure arithmetic with no gesture/view involved, so it can catch a
/// regression in the dial's math even without a simulator.
final class MinuteDialMathTests: XCTestCase {
    private let stepWidth: CGFloat = 18
    private let range = 5...180

    private func minute(base: Int, translation: CGFloat) -> Int {
        MinuteDialMath.minute(base: base, translation: translation, stepWidth: stepWidth, range: range)
    }

    // MARK: - Start at 30, nudge higher, nudge lower

    func testDraggingLeftFromThirtyIncreasesMinutes() {
        // Dragging left is a negative translation and must increase the value.
        XCTAssertEqual(minute(base: 30, translation: -stepWidth), 31)
        XCTAssertEqual(minute(base: 30, translation: -stepWidth * 2), 32)
    }

    func testDraggingRightFromThirtyDecreasesMinutes() {
        XCTAssertEqual(minute(base: 30, translation: stepWidth), 29)
        XCTAssertEqual(minute(base: 30, translation: stepWidth * 2), 28)
    }

    func testSmallSubStepMovementDoesNotJumpAHalfStepEarly() {
        // Less than half a step shouldn't move the selection yet...
        XCTAssertEqual(minute(base: 30, translation: -(stepWidth / 2 - 1)), 30)
        // ...but just past half a step commits to the next minute, and only that one.
        XCTAssertEqual(minute(base: 30, translation: -(stepWidth / 2 + 1)), 31)
    }

    // MARK: - Several consecutive movements in the same direction (one continuous gesture)

    func testConsecutiveMovementsLeftAreMonotonicNonDecreasing() {
        let translations: [CGFloat] = [-5, -10, -18, -30, -45, -60, -90]
        let minutes = translations.map { minute(base: 30, translation: $0) }
        for (previous, next) in zip(minutes, minutes.dropFirst()) {
            XCTAssertLessThanOrEqual(previous, next, "Moving further left must never decrease the minute")
        }
        XCTAssertEqual(minutes, minutes.sorted())
    }

    func testConsecutiveMovementsRightAreMonotonicNonIncreasing() {
        let translations: [CGFloat] = [5, 10, 18, 30, 45, 60, 90]
        let minutes = translations.map { minute(base: 30, translation: $0) }
        for (previous, next) in zip(minutes, minutes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(previous, next, "Moving further right must never increase the minute")
        }
        XCTAssertEqual(minutes, minutes.sorted(by: >))
    }

    // MARK: - Reversing direction mid-gesture

    func testReversingDirectionWithinASingleGestureTracksBackCorrectly() {
        // All measured from the SAME base (30): a real continuous drag
        // reports translation relative to its own start point, never as
        // frame-to-frame deltas, so reversing mid-gesture must retrace
        // exactly rather than drift.
        XCTAssertEqual(minute(base: 30, translation: -50), 33)  // drag left
        XCTAssertEqual(minute(base: 30, translation: -20), 31)  // partially back
        XCTAssertEqual(minute(base: 30, translation: 0), 30)    // back to the start
        XCTAssertEqual(minute(base: 30, translation: 20), 29)   // past the start, right
    }

    // MARK: - Presets, and interacting with the dial again afterward

    func testPresetChangesTheBaseForTheNextGesture() {
        // A preset tap becomes the dial's new committed base (see
        // MinuteDialView.onChange(of: selectedMinutes)); the next gesture
        // must compute from that new base, not any earlier one.
        let afterPreset = 45
        XCTAssertEqual(minute(base: afterPreset, translation: 0), 45)
        XCTAssertEqual(minute(base: afterPreset, translation: -stepWidth), 46)
        XCTAssertEqual(minute(base: afterPreset, translation: stepWidth * 3), 42)
    }

    // MARK: - Boundaries

    func testClampsAtLowerBoundWithoutOvershooting() {
        XCTAssertEqual(minute(base: 10, translation: stepWidth * 1000), range.lowerBound)
    }

    func testClampsAtUpperBoundWithoutOvershooting() {
        XCTAssertEqual(minute(base: 170, translation: -stepWidth * 1000), range.upperBound)
    }

    func testRecoversImmediatelyAfterHittingABoundary() {
        let base = 10
        // Drag far past the lower bound: hard clamp, no rubber-banding.
        XCTAssertEqual(minute(base: base, translation: 1000), range.lowerBound)
        // Ease back within the same gesture: as soon as translation
        // re-enters the valid range the dial must resume tracking the
        // finger immediately, not stay stuck at the boundary.
        XCTAssertEqual(minute(base: base, translation: 80), 6)
        XCTAssertEqual(minute(base: base, translation: 60), 7)
        XCTAssertEqual(minute(base: base, translation: 0), base)
    }

    // MARK: - The displayed dial position always matches the selected value

    func testFractionalPositionAlwaysRoundsToTheReturnedMinute() {
        for translation in stride(from: CGFloat(-200), through: 200, by: 7) {
            let base = 90
            let fractional = MinuteDialMath.fractionalMinute(base: base, translation: translation, stepWidth: stepWidth, range: range)
            XCTAssertEqual(Int(fractional.rounded()), minute(base: base, translation: translation))
        }
    }
}
