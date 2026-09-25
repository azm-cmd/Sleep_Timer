import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var manager: SleepTimerManager
    @AppStorage("com.azm.sleeptimer.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            if manager.isRunning {
                RunningView()
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
            } else if manager.didFinish {
                FinishedView()
                    .transition(.opacity)
            } else {
                SetupView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: manager.isRunning)
        .animation(.easeInOut(duration: 0.6), value: manager.didFinish)
        .fullScreenCover(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { hasCompletedOnboarding = !$0 })) {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}
