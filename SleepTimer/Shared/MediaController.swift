import AVFoundation

/// Abstraction for issuing a generic "pause whatever is currently playing"
/// request to the system, and for keeping the app's own process alive in
/// the background for as long as a timer is running. Kept separate from
/// `SleepTimerManager` so the timer's own logic never depends on media
/// playback being available, active, or even meaningful — nothing playing
/// is a legitimate, silent no-op, and the timer must finish normally
/// either way.
protocol MediaPausing {
    func pauseCurrentMedia()
    /// Starts a silent, *mixing* background-audio session so the app's
    /// process is exempted from suspension for as long as a timer is
    /// running — this is what lets `pauseCurrentMedia()` (and the timer's
    /// own per-second tick) actually fire at the right moment even while
    /// backgrounded or locked, not just the next time the app is
    /// foregrounded. Mixing means it never interrupts whatever the person
    /// is already listening to. Idempotent — safe to call again while
    /// already active (e.g. from `addTime`, or re-syncing after a relaunch).
    func beginBackgroundKeepAlive()
    /// Stops the keep-alive session without pausing anything — for a
    /// deliberate cancel, where no pause should happen at all. A natural
    /// completion instead goes straight through `pauseCurrentMedia()`,
    /// which folds the equivalent teardown into its own exclusive-session
    /// transition rather than calling this first.
    func endBackgroundKeepAlive()
}

/// Pauses system media using the same mechanism iOS itself relies on
/// whenever two playback apps conflict — a phone call arriving, Siri
/// activating, another app starting playback, and so on: briefly taking
/// audio focus with our own `AVAudioSession`. Also keeps that same session
/// alive (in a non-interrupting form) for the life of a running timer, so
/// the pause can actually happen on time while backgrounded.
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
/// The actual pause mechanism: briefly play genuine (silent) audio through
/// an exclusive `.playback`-category session, the same way switching from
/// one music app to another pauses the first. Playing genuine audio -
/// rather than only activating the session with nothing ever rendered -
/// is what reliably counts as the kind of interruption every App
/// Store-compliant playback app is required to honor.
///
/// **Why there's a background keep-alive at all:** none of that matters if
/// the app is suspended when the timer actually reaches zero - a plain app
/// with no active background mode gets zero CPU time shortly after being
/// backgrounded, so neither the per-second tick nor the pause call can run
/// until the app is next foregrounded. The `audio` background mode is
/// Apple's real exemption from that: an app that keeps a genuinely active,
/// rendering `AVAudioSession` is kept alive by the OS on the same
/// assumption a podcast or music app relies on, and once that's true, every
/// line of the app's code keeps running on schedule, including a 1-second
/// UI timer with nothing to do with audio. This project avoided that
/// mode previously only because of a review-policy risk (Apple's Guideline
/// 2.5.4 lets a human reviewer reject an app that requests it without a
/// genuine continuous-audio product need) - since this app is sideloaded
/// and never submitted for App Store review, that risk doesn't apply, and
/// the underlying OS mechanism works the same either way.
///
/// The keep-alive session uses `.mixWithOthers` and plays true digital
/// silence in a loop, so it never interrupts, ducks, or is audible over
/// whatever the person is actually listening to while the timer counts
/// down - only `pauseCurrentMedia()`'s brief switch to an exclusive session
/// at the end is meant to affect anything audible.
final class MediaController: MediaPausing {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pauseSignalDuration: TimeInterval = 2.0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var isGraphWired = false
    private var isKeepAliveActive = false
    private var pendingStop: DispatchWorkItem?

    func beginBackgroundKeepAlive() {
        guard !isKeepAliveActive else { return }
        pendingStop?.cancel()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            wireGraphIfNeeded()

            guard let loopBuffer = silentBuffer(duration: 1.0) else {
                deactivateSession()
                return
            }
            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(loopBuffer, at: nil, options: .loops, completionHandler: nil)
            player.play()
            isKeepAliveActive = true
        } catch {
            // No audio session was available to take. The timer itself is
            // unaffected either way - the pause at completion (and the
            // tick that drives it) will simply catch up the next time the
            // app is foregrounded instead, same as before this existed.
        }
    }

    func endBackgroundKeepAlive() {
        guard isKeepAliveActive else { return }
        pendingStop?.cancel()
        player.stop()
        engine.stop()
        isKeepAliveActive = false
        // No .notifyOthersOnDeactivation: harmless either way here, since
        // .mixWithOthers never interrupted anything to begin with, but kept
        // consistent with pauseCurrentMedia()'s deactivation below.
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func pauseCurrentMedia() {
        pendingStop?.cancel()
        player.stop()
        isKeepAliveActive = false

        let session = AVAudioSession.sharedInstance()
        do {
            // Deactivate and reconfigure to an *exclusive* (non-mixing)
            // session before reactivating - that transition, switching from
            // either nothing or a mixing keep-alive into an exclusive
            // .playback session, is what actually asks iOS to interrupt
            // whatever else is playing.
            try? session.setActive(false)
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            wireGraphIfNeeded()

            guard let buffer = silentBuffer(duration: pauseSignalDuration) else {
                deactivateSession()
                return
            }
            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(buffer, completionHandler: nil)
            player.play()

            let stopWork = DispatchWorkItem { [self] in
                stopPlaybackAndDeactivate()
                pendingStop = nil
            }
            pendingStop = stopWork
            DispatchQueue.main.asyncAfter(deadline: .now() + pauseSignalDuration, execute: stopWork)
        } catch {
            // No audio session or engine was available to take, or nothing
            // was playing to interrupt. Either way there is nothing more to
            // do safely — pausing is always best-effort.
            deactivateSession()
        }
    }

    private func wireGraphIfNeeded() {
        guard !isGraphWired else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isGraphWired = true
    }

    /// A zero-filled `AVAudioPCMBuffer` of the given duration. Used both for
    /// the looping background keep-alive and the one-shot pause signal -
    /// `AVAudioPCMBuffer` isn't documented as pre-zeroed, and this must
    /// never be audible either way: someone hears this because they're
    /// trying to sleep, not because they tapped play.
    private func silentBuffer(duration: TimeInterval) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData {
            let byteCount = Int(frameCount) * MemoryLayout<Float>.size
            for channel in 0..<Int(format.channelCount) {
                memset(channelData[channel], 0, byteCount)
            }
        }
        return buffer
    }

    private func stopPlaybackAndDeactivate() {
        player.stop()
        engine.stop()
        deactivateSession()
    }

    private func deactivateSession() {
        // No .notifyOthersOnDeactivation: that option tells whichever app
        // we just interrupted "it's safe to resume now," which would undo
        // the pause almost immediately — the WhatsApp-voice-note behavior
        // this is deliberately avoiding. Omitting it leaves that app paused
        // until the person resumes it themselves, the same as switching to
        // a different music app and never switching back.
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}
