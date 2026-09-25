import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: SleepTimerManager

    var body: some View {
        ZStack {
            if manager.isRunning {
                RunningView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else {
                SetupView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: manager.isRunning)
    }
}
