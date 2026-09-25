import AppIntents

/// Registers Sleep Timer's App Shortcuts. This is the one piece of the
/// media-pause automation story iOS lets a third-party app do fully
/// automatically: once the app is installed, `PauseCurrentMediaIntent`
/// simply appears — in Siri, in Spotlight, and in the Shortcuts app's
/// per-app action list — with no setup, no button to tap, no permission
/// prompt. What iOS does *not* allow (verified, not assumed — see
/// README.md's "Setting up automatic media pause" section) is a third-party
/// app creating or installing a personal automation on someone's behalf, or
/// a personal automation triggered by another app's notification at all —
/// no such trigger exists in Shortcuts. So this is as far as "automatic"
/// goes; the rest of the flow (building an automation that calls this
/// action) is necessarily manual, and OnboardingView walks through it.
struct SleepTimerAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PauseCurrentMediaIntent(),
            phrases: [
                "Pause current media with \(.applicationName)",
                "Pause media with \(.applicationName)",
            ],
            shortTitle: "Pause Current Media",
            systemImageName: "pause.circle.fill"
        )
    }
}
