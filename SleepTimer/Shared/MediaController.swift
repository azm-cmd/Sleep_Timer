import AVFoundation

/// Abstraction for issuing a generic "pause whatever is currently playing"
/// request to the system. Kept separate from `SleepTimerManager` so the
/// timer's own logic never depends on media playback being available,
/// active, or even meaningful — nothing playing is a legitimate, silent
/// no-op, and the timer must finish normally either way.
protocol MediaPausing {
    func pauseCurrentMedia()
}

/// Pauses system media using the same mechanism iOS itself relies on
/// whenever two playback apps conflict — a phone call arriving, Siri
/// activating, another app starting playback, and so on: briefly taking
/// audio focus with our own `AVAudioSession`.
///
/// `MPRemoteCommandCenter` was investigated first, since it's the API most
/// commonly associated with "media remote control." It is not sufficient on
/// its own here: its commands only let an app *receive* remote-control
/// events (lock screen, headphones, CarPlay) that the system has already
/// routed to whichever app currently owns "Now Playing" status. There is no
/// public API on `MPRemoteCommandCenter` or `MPNowPlayingInfoCenter` that
/// lets one app send a pause command to a *different* app's media session —
/// Sleep Timer isn't a media player and has no Now Playing session for a
/// command to be routed through in the first place.
///
/// The actual, documented, App Review-safe mechanism for one app to affect
/// "whatever is currently playing" without knowing or caring which app that
/// is: activate an `AVAudioSession` with the `.playback` category. Every
/// App Store-compliant playback app is required to handle audio session
/// interruptions by pausing — the same contract that makes a phone call or
/// a Siri request silence background music — so briefly taking, then
/// releasing, audio focus this way asks the system to interrupt whatever
/// else is playing, generically, without targeting any specific app.
final class MediaController: MediaPausing {
    func pauseCurrentMedia() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            // Deactivate *without* .notifyOthersOnDeactivation: that option
            // tells whichever app we just interrupted "it's safe to resume
            // now," which would undo the pause almost immediately. Omitting
            // it leaves that app paused until the person resumes it
            // themselves — the point of a sleep timer.
            try session.setActive(false)
        } catch {
            // No audio session was available to take, or nothing was
            // playing to interrupt. Either way there is nothing more to do
            // safely — pausing is always best-effort.
        }
    }
}
