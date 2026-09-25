import SwiftUI

/// Shown once the timer reaches zero, replacing the countdown so the screen
/// never sits stuck at "00:00". Mirrors RunningView's two-tier text layout
/// (a small tracked caption over a large primary line) and uses the same
/// fully-dark end state as `DarkeningBackground(progress:)` reaches at 1 —
/// calm and clearly a resting state, not a discrete theme swap.
struct FinishedView: View {
    @EnvironmentObject private var manager: SleepTimerManager

    var body: some View {
        ZStack {
            DarkeningBackground(progress: 1)

            VStack(spacing: 44) {
                Spacer()

                VStack(spacing: 10) {
                    Text("SLEEP TIMER ENDED")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))

                    Text("Good Night")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        manager.acknowledgeFinished()
                    }
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
    }
}
