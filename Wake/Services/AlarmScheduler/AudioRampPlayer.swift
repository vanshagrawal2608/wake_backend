import Foundation
import AVFoundation

/// Plays the wake soundscape and smoothly ramps volume as stages escalate.
/// This is the "gentle music keeps playing" layer — it runs while the app holds
/// an active `audio` background session (the same legitimate mechanism Sleep Cycle
/// uses). The notification ladder is the reliable floor beneath it.
final class AudioRampPlayer {
    private var player: AVAudioPlayer?
    private var rampTimer: Timer?
    private(set) var currentIntensity: Double = 0

    /// Begin (or continue) the soundscape at a given stage intensity, easing from
    /// wherever we are now to the new target over `duration` seconds.
    func play(soundscape: WakeStage.Soundscape, targetIntensity: Double, over duration: TimeInterval = 20) {
        configureSession()
        ensurePlayer(for: soundscape)
        ramp(to: volume(for: targetIntensity), over: duration)
    }

    func stop() {
        rampTimer?.invalidate(); rampTimer = nil
        player?.setVolume(0, fadeDuration: 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.player?.stop(); self?.player = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - Internals

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps sound going with the screen locked / app backgrounded,
        // provided the `audio` background mode is enabled in the target.
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    private func ensurePlayer(for soundscape: WakeStage.Soundscape) {
        // TODO(device): bundle .caf/.m4a assets named after each soundscape.
        guard player == nil,
              let url = Bundle.main.url(forResource: soundscape.rawValue, withExtension: "m4a")
        else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1        // loop through the window
        player?.volume = Float(volume(for: currentIntensity))
        player?.play()
    }

    /// Map 0…1 intensity to a perceptually gentle volume curve (quadratic — early
    /// stages stay genuinely quiet, so we never blast at maximum from the start).
    private func volume(for intensity: Double) -> Double {
        let clamped = min(max(intensity, 0), 1)
        return clamped * clamped
    }

    private func ramp(to target: Double, over duration: TimeInterval) {
        rampTimer?.invalidate()
        guard let player else { currentIntensity = target; return }
        let steps = 40
        let start = Double(player.volume)
        let delta = (target - start) / Double(steps)
        var i = 0
        rampTimer = Timer.scheduledTimer(withTimeInterval: duration / Double(steps), repeats: true) { [weak self] t in
            i += 1
            player.volume = Float(min(max(start + delta * Double(i), 0), 1))
            if i >= steps { t.invalidate(); self?.currentIntensity = target }
        }
    }
}
