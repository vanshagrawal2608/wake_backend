import Foundation
import AVFoundation

/// Uses Apple's **Personal Voice** (iOS 17+, free, on-device) to render a wake-up line
/// in the user's own voice. The voice itself is created by the user in
/// Settings → Accessibility → Personal Voice; apps request permission to use it.
///
/// We render the line to an audio file once (when the alarm is configured) so there's
/// no synthesis/latency at 6am — the file becomes the alarm's sound and escalates
/// through the wake stages like any other clip.
final class PersonalVoiceSpeaker {
    /// Ask the user to allow this app to use their Personal Voice.
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    var isAuthorized: Bool {
        AVSpeechSynthesizer.personalVoiceAuthorizationStatus == .authorized
    }

    /// The user's Personal Voice, if they've created one and authorized us.
    var personalVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices().first { $0.voiceTraits.contains(.isPersonalVoice) }
    }

    private var synth: AVSpeechSynthesizer?   // retained during rendering

    /// Render `text` in the Personal Voice to a temp .caf file; nil if unavailable.
    func render(text: String) async -> URL? {
        guard let voice = personalVoice else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            let synth = AVSpeechSynthesizer()
            self.synth = synth
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pv-\(UUID().uuidString).caf")
            var file: AVAudioFile?
            var resumed = false
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice

            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {                        // final empty buffer = done
                    if !resumed { resumed = true; cont.resume(returning: file != nil ? url : nil) }
                    return
                }
                if file == nil {
                    file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                            commonFormat: pcm.format.commonFormat,
                                            interleaved: pcm.format.isInterleaved)
                }
                try? file?.write(from: pcm)
            }
        }
    }
}
