import Foundation
#if canImport(Speech)
import Speech
import AVFoundation
#endif

/// Captures the morning "I'm awake" on-device and scores how clearly it was said.
/// No enrollment/baseline: the decision is clarity of the exact phrase (and Gemini
/// when the local score is unsure — see `WakeJudge`).
protocol VoiceWakeVerifying: AnyObject {
    func requestAuthorization() async -> Bool
    /// Stream readings as the user speaks; the final one carries the clip + clarity.
    func listen(onResult: @escaping (Wakefulness) -> Void)
    func stop()
    /// The recorded audio of the last utterance (for Gemini). Populated by the final result.
    var lastClipData: Data? { get }
}

/// A single reading of the morning utterance.
struct Wakefulness: Equatable {
    let heardExpectedPhrase: Bool     // said exactly "I'm awake"
    let clarity: Double               // mean recognizer confidence — how crisply spoken
    let transcript: String
    let isFinal: Bool

    static let empty = Wakefulness(heardExpectedPhrase: false, clarity: 0, transcript: "", isFinal: false)
}

final class VoiceWakeVerifier: VoiceWakeVerifying {
    private(set) var lastClipData: Data?

    /// The alarm only accepts **"I'm awake"** — tolerant spellings of that one phrase.
    private let acceptedForms = ["i'm awake", "im awake", "i am awake"]
    private let openerForms   = ["i'm", "im", "i am"]
    private let requiredWords = ["awake"]

    #if canImport(Speech)
    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
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

    // MARK: - Listening

    func listen(onResult: @escaping (Wakefulness) -> Void) {
        #if canImport(Speech)
        guard let recognizer, recognizer.isAvailable else { onResult(.empty); return }
        stop()
        lastClipData = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = false
        self.request = request

        // TODO(device): also tap into an AVAudioFile here to capture the clip as m4a
        // and set `lastClipData` on stop — that's what gets sent to Gemini when unsure.
        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try? audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, let result else { return }
            onResult(self.reading(from: result.bestTranscription, isFinal: result.isFinal))
            if error != nil || result.isFinal { self.stop() }
        }
        #else
        onResult(.empty)
        #endif
    }

    func stop() {
        #if canImport(Speech)
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Scoring

    #if canImport(Speech)
    private func reading(from transcription: SFTranscription, isFinal: Bool) -> Wakefulness {
        let confs = transcription.segments.map { Double($0.confidence) }.filter { $0 > 0 }
        let clarity = confs.isEmpty ? 0.35 : confs.reduce(0, +) / Double(confs.count)
        return makeReading(text: transcription.formattedString, recognizerClarity: clarity, isFinal: isFinal)
    }
    #endif

    /// Pure scoring core — unit-testable without audio hardware.
    func makeReading(text: String, recognizerClarity: Double, isFinal: Bool) -> Wakefulness {
        let norm = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let saidExactPhrase = acceptedForms.contains { norm.contains($0) }
        return Wakefulness(heardExpectedPhrase: saidExactPhrase,
                           clarity: min(max(recognizerClarity, 0), 1),
                           transcript: text,
                           isFinal: isFinal)
    }
}
