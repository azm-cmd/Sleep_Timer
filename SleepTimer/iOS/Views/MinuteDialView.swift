import SwiftUI

/// A horizontal, tactile minute-ruler.
///
/// The dial always exists visually, but the big numeral only animates up
/// "from nowhere" once the person actually drags it — a preset tap moves the
/// ruler to match without revealing the numeral, since that wasn't a direct
/// interaction with the dial.
///
/// Position is driven entirely by a plain `DragGesture` translated into
/// arithmetic (`committedMinutes - translation / stepWidth`, clamped) rather
/// than `ScrollView`/`.scrollPosition(id:)`. That API resolves position by
/// picking the "nearest id to the anchor" on every render pass — a heuristic
/// meant for snapping between a handful of large paged cards — and applying
/// it to ~176 tick views spaced 18pt apart let it occasionally misreport the
/// centered id under real touch/momentum, which a bidirectional binding to
/// `selectedMinutes` then turned into a sticky, visible "jump". Plain drag
/// translation has no such resolution step: the minute is always an exact,
/// monotonic function of how far the finger has moved from where the drag
/// started.
struct MinuteDialView: View {
    @Binding var selectedMinutes: Int
    var range: ClosedRange<Int> = 5...180

    /// The minute the dial was at when the current drag (if any) began.
    /// Fixed for the entire duration of a single gesture so translation-based
    /// math never double-counts movement already applied.
    @State private var committedMinutes: Int = 0
    /// Raw, continuous translation of the drag in progress; zero at rest.
    @State private var dragTranslation: CGFloat = 0
    @State private var hasInteracted = false
    @GestureState private var isDragging = false

    /// Pixel distance between adjacent tick centers. A single source of
    /// truth for both layout and gesture math, so they can never drift apart.
    private let stepWidth: CGFloat = 18

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if hasInteracted {
                    Text("\(selectedMinutes)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                }
            }
            .frame(height: 54)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: selectedMinutes)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: hasInteracted)

            GeometryReader { geometry in
                let liveOffsetMinutes = clampedFloatMinute(translation: dragTranslation)
                let contentCenterX = (liveOffsetMinutes - CGFloat(range.lowerBound) + 0.5) * stepWidth
                let renderOffsetX = geometry.size.width / 2 - contentCenterX

                HStack(spacing: 0) {
                    ForEach(range, id: \.self) { minute in
                        TickMark(minute: minute, width: stepWidth)
                    }
                }
                .offset(x: renderOffsetX)
                // Only the settle-into-place transition (committedMinutes changing,
                // e.g. on release or a preset tap) is animated; live drag tracking
                // must stay perfectly 1:1 with the finger, unanimated.
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: committedMinutes)
                .frame(width: geometry.size.width, height: 56, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { value in
                            hasInteracted = true
                            dragTranslation = value.translation.width
                            let newMinute = clampedMinute(translation: dragTranslation)
                            if newMinute != selectedMinutes {
                                selectedMinutes = newMinute
                            }
                        }
                        .onEnded { value in
                            let finalMinute = clampedMinute(translation: value.translation.width)
                            committedMinutes = finalMinute
                            selectedMinutes = finalMinute
                            dragTranslation = 0
                        }
                )
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 2, height: 34)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 56)
        }
        .sensoryFeedback(.selection, trigger: selectedMinutes)
        .onChange(of: selectedMinutes) { _, newValue in
            // A preset tap (or any other external write) lands here too. Only
            // adopt it as the dial's new resting position while no gesture is
            // live — otherwise this would overwrite `committedMinutes` mid-drag
            // and corrupt the translation math for the rest of that gesture.
            guard !isDragging else { return }
            if committedMinutes != newValue {
                committedMinutes = newValue
            }
        }
        .onAppear {
            committedMinutes = selectedMinutes
        }
    }

    /// Fractional minute position implied by `translation`, clamped to `range`.
    /// Dragging left (negative translation) moves toward higher minutes.
    private func clampedFloatMinute(translation: CGFloat) -> CGFloat {
        MinuteDialMath.fractionalMinute(base: committedMinutes, translation: translation, stepWidth: stepWidth, range: range)
    }

    private func clampedMinute(translation: CGFloat) -> Int {
        MinuteDialMath.minute(base: committedMinutes, translation: translation, stepWidth: stepWidth, range: range)
    }
}

/// Pure position arithmetic for `MinuteDialView`, factored out from the view
/// so it can be exercised directly in unit tests without a live gesture.
enum MinuteDialMath {
    /// The fractional minute implied by dragging `translation` points from
    /// `base`, clamped to `range`. Dragging left (negative translation)
    /// increases the minute; dragging right decreases it. This is the only
    /// place position is computed — the same call drives both what's drawn
    /// and what's selected, so they can never disagree with each other.
    static func fractionalMinute(base: Int, translation: CGFloat, stepWidth: CGFloat, range: ClosedRange<Int>) -> CGFloat {
        let raw = CGFloat(base) - translation / stepWidth
        return min(CGFloat(range.upperBound), max(CGFloat(range.lowerBound), raw))
    }

    static func minute(base: Int, translation: CGFloat, stepWidth: CGFloat, range: ClosedRange<Int>) -> Int {
        Int(fractionalMinute(base: base, translation: translation, stepWidth: stepWidth, range: range).rounded())
    }
}

private struct TickMark: View {
    let minute: Int
    let width: CGFloat

    private var isMajor: Bool { minute % 15 == 0 }
    private var isMid: Bool { minute % 5 == 0 }

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            Capsule()
                .fill(Color.white.opacity(isMajor ? 0.9 : (isMid ? 0.55 : 0.25)))
                .frame(width: isMajor ? 3 : 2, height: isMajor ? 28 : (isMid ? 18 : 11))
            Text(isMajor ? "\(minute)" : "")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: 14)
        }
        .frame(width: width, height: 56)
    }
}
