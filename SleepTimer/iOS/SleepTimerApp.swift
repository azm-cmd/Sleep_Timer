import SwiftUI

@main
struct SleepTimerApp: App {
    @StateObject private var manager = SleepTimerManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                manager.refreshFromPersistence()
            }
        }
    }
}
