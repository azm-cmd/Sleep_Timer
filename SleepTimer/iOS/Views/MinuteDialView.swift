import SwiftUI

/// A horizontal, tactile minute-ruler.
///
/// The dial always exists visually, but the big numeral only animates up
/// "from nowhere" once the person actually drags it — a preset tap moves the
/// ruler to match without revealing the numeral, since that wasn't a direct
/// interaction with the dial.
struct MinuteDialView: View {
    @Binding var selectedMinutes: Int
    var range: ClosedRange<Int> = 5...180

    @State private var scrollPosition: Int?
    @State private var hasInteracted = false

    private let tickSpacing: CGFloat = 14

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if hasInteracted {
                    Text("\(scrollPosition ?? selectedMinutes)")
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
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: scrollPosition)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: hasInteracted)

            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: tickSpacing) {
                        ForEach(range, id: \.self) { minute in
                            TickMark(minute: minute)
                                .id(minute)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, geometry.size.width / 2)
                }
                .scrollPosition(id: $scrollPosition, anchor: .center)
                .scrollTargetBehavior(.viewAligned)
                .onScrollPhaseChange { _, newPhase in
                    if newPhase == .interacting || newPhase == .decelerating {
                        hasInteracted = true
                    }
                }
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 2, height: 34)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 56)
        }
        .sensoryFeedback(.selection, trigger: scrollPosition)
        .onChange(of: scrollPosition) { _, newValue in
            if let newValue {
                selectedMinutes = newValue
            }
        }
        .onChange(of: selectedMinutes) { _, newValue in
            if scrollPosition != newValue {
                scrollPosition = newValue
            }
        }
        .onAppear {
            scrollPosition = selectedMinutes
        }
    }
}

private struct TickMark: View {
    let minute: Int

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
        .frame(width: 4, height: 56)
    }
}
