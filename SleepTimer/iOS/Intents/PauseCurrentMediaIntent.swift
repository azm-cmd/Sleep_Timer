import AppIntents

/// Exposes "Pause Current Media" to Siri, Spotlight, and the Shortcuts
/// app's action library via `SleepTimerAppShortcuts` — the legitimate,
/// zero-setup way for a third-party app to make an action available inside
/// Shortcuts. It's a standalone action, independent of any running timer:
/// this is exactly what Sleep Timer's own countdown calls when it reaches
/// zero (`MediaController`'s `AVAudioSession` interruption), just made
/// available for someone to run on their own — from Siri, Spotlight, or
/// dropped into whatever automation they build themselves.
struct PauseCurrentMediaIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Current Media"
    static var description = IntentDescription(
        "Pauses whatever is currently playing — the same way Sleep Timer pauses it automatically when its countdown ends."
    )

    func perform() async throws -> some IntentResult {
        MediaController().pauseCurrentMedia()
        return .result()
    }
}
