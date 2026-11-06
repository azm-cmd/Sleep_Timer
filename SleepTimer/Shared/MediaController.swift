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
/// The actual mechanism: briefly play genuine (silent) audio through an
/// exclusive `.playback`-category session, the same way switching from one
/// music app to another pauses the first. Earlier this only activated the
/// session (`setActive(true)`/`setActive(false)`, no audio ever rendered) —
/// that's the weaker half of the same trick, and isn't reliably treated as
/// a real interruption by every app: the behavior other playback apps are
/// actually required to honor is an interruption caused by genuine
/// concurrent audio engagement, not merely another session existing in the
/// active state. Running an `AVAudioEngine` that actually renders a couple
/// of seconds of true digital silence - inaudible, but real audio output -
/// is what makes this match the same "another app started playing" signal
/// a real player would send, rather than something closer to a voice-note
/// style blip.
final class MediaController: MediaPausing {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let silenceDuration: TimeInterval = 2.0
    private var isGraphWired = false
    private var pendingStop: DispatchWorkItem?

    func pauseCurrentMedia() {
        pendingStop?.cancel()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)

            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            wireGraphIfNeeded(format: format)

            let frameCount = AVAudioFrameCount(format.sampleRate * silenceDuration)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                deactivateSession()
                return
            }
            buffer.frameLength = frameCount
            zeroFill(buffer)

            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(buffer, completionHandler: nil)
            player.play()

            let stopWork = DispatchWorkItem { [weak self] in
                self?.stopPlaybackAndDeactivate()
            }
            pendingStop = stopWork
            DispatchQueue.main.asyncAfter(deadline: .now() + silenceDuration, execute: stopWork)
        } catch {
            // No audio session or engine was available to take. Either way
            // there is nothing more to do safely — pausing is always
            // best-effort.
            deactivateSession()
        }
    }

    private func wireGraphIfNeeded(format: AVAudioFormat) {
        guard !isGraphWired else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isGraphWired = true
    }

    /// `AVAudioPCMBuffer` isn't documented as pre-zeroed, and this one must
    /// never be audible — someone hears this because they're trying to
    /// sleep, not because they tapped play.
    private func zeroFill(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let byteCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(buffer.format.channelCount) {
            memset(channelData[channel], 0, byteCount)
        }
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
