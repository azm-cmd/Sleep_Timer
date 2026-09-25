import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var manager: SleepTimerManager

    var body: some View {
        ZStack {
            if manager.isRunning {
                WatchRunningView()
            } else if manager.didFinish {
                WatchFinishedView()
            } else {
                WatchSetupView()
            }
        }
        .animation(.easeInOut(duration: 0.5), value: manager.isRunning)
        .animation(.easeInOut(duration: 0.5), value: manager.didFinish)
    }
}
