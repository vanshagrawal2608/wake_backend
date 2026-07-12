import Foundation
#if canImport(Speech)
import Speech
import AVFoundation
#endif

/// Captures the morning "I'm awake" and scores how clearly it was said — no baseline.
/// It records a short `.m4a`, recognises it on-device (clarity + phrase), and keeps the
/// clip in `lastClipData` so `GeminiDirectJudge` can send it when the local call is unsure.
protocol VoiceWakeVerifying: AnyObject {
    func requestAuthorization() async -> Bool
    /// Record for `seconds`, recognise on-device, return the reading. Also sets `lastClipData`.
    func capture(seconds: TimeInterval) async -> Wakefulness
    func stop()
    var lastClipData: Data? { get }
}

/// A reading of the morning utterance.
struct Wakefulness: Equatable {
    let heardExpectedPhrase: Bool     // said exactly "I'm awake"
    let clarity: Double               // mean recognizer confidence — how crisply spoken
    let transcript: String
    let isFinal: Bool

    static let empty = Wakefulness(heardExpectedPhrase: false, clarity: 0, transcript: "", isFinal: true)
}

final class VoiceWakeVerifier: VoiceWakeVerifying {
    private(set) var lastClipData: Data?

    /// The alarm only accepts **"I'm awake"** — tolerant spellings of that one phrase.
    private let acceptedForms = ["i'm awake", "im awake", "i am awake"]

    #if canImport(Speech)
    private let recognizer = SFSpeechRecognizer()
    private var recorder: AVAudioRecorder?
    private var clipURL: URL?
    #endif

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        #if canImport(Speech)
        let speechOK = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
        return speechOK && micOK
        #else
        return false
        #endif
    }

    // MARK: - Capture

    func capture(seconds: TimeInterval = 3.5) async -> Wakefulness {
        #if canImport(Speech)
        guard let recognizer, recognizer.isAvailable else { return .empty }
        lastClipData = nil

        // 1) Record a short clip to a small mono AAC .m4a (perfect for Gemini + speech).
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wake-\(UUID().uuidString).m4a")
        clipURL = url
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,        // 16 kHz mono — plenty for speech, tiny upload
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return .empty }
        self.recorder = recorder
        recorder.record()
        try? await Task.sleep(for: .seconds(seconds))
        recorder.stop()
        self.recorder = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        lastClipData = try? Data(contentsOf: url)

        // 2) Recognise the recording. Prefer on-device (private) on real hardware.
        //    The Simulator's local speech service is broken (error 1101), so there we
        //    force server-based recognition, which works with a network connection.
        let request = SFSpeechURLRecognitionRequest(url: url)
        #if targetEnvironment(simulator)
        request.requiresOnDeviceRecognition = false
        #else
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        #endif
        request.addsPunctuation = false

        let result: SFSpeechRecognitionResult? = await withCheckedContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if resumed { return }                      // task callback is serialized → safe
                if let result, result.isFinal { resumed = true; cont.resume(returning: result) }
                else if error != nil { resumed = true; cont.resume(returning: nil) }
            }
        }

        // 3) Clean up the temp file (we've already copied its bytes into lastClipData).
        try? FileManager.default.removeItem(at: url)
        clipURL = nil

        guard let result else {
            return Wakefulness(heardExpectedPhrase: false, clarity: 0.2, transcript: "", isFinal: true)
        }
        return reading(from: result.bestTranscription)
        #else
        return .empty
        #endif
    }

    func stop() {
        #if canImport(Speech)
        recorder?.stop(); recorder = nil
        if let url = clipURL { try? FileManager.default.removeItem(at: url); clipURL = nil }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Scoring

    #if canImport(Speech)
    private func reading(from transcription: SFTranscription) -> Wakefulness {
        let confs = transcription.segments.map { Double($0.confidence) }.filter { $0 > 0 }
        let clarity = confs.isEmpty ? 0.35 : confs.reduce(0, +) / Double(confs.count)
        return makeReading(text: transcription.formattedString, recognizerClarity: clarity)
    }
    #endif

    /// Pure scoring core — unit-testable without audio hardware.
    func makeReading(text: String, recognizerClarity: Double) -> Wakefulness {
        let norm = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let saidExactPhrase = acceptedForms.contains { norm.contains($0) }
        return Wakefulness(heardExpectedPhrase: saidExactPhrase,
                           clarity: min(max(recognizerClarity, 0), 1),
                           transcript: text,
                           isFinal: true)
    }
}
