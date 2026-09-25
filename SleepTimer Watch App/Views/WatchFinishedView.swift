import SwiftUI

/// Watch equivalent of FinishedView: replaces the countdown once the timer
/// reaches zero so the Watch screen never sits stuck at "00:00" either.
struct WatchFinishedView: View {
    @EnvironmentObject private var manager: SleepTimerManager

    var body: some View {
        ZStack {
            DarkeningBackground(progress: 1)

            VStack(spacing: 14) {
                Text("Good Night")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Button {
                    manager.acknowledgeFinished()
                } label: {
                    Text("Done")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .padding(.horizontal, 12)
        }
    }
}
