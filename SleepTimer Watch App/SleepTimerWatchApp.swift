import SwiftUI

@main
struct SleepTimerWatchApp: App {
    @StateObject private var manager = SleepTimerManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(manager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                manager.refreshFromPersistence()
            }
        }
    }
}
