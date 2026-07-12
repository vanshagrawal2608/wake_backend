import Foundation

/// The awake/not-awake decision. No baseline — judged from how clearly the exact
/// phrase "I'm awake" was spoken, locally, and by Gemini when the local score is unsure.
struct WakeDecision: Equatable {
    let isAwake: Bool
    let clarity: Double        // 0…1 on-device clarity
    let confidence: Double     // final confidence (local clarity, or Gemini's rating)
    let heardPhrase: Bool
    let reasoning: String
    let source: Source

    enum Source: String { case local, gemini, offline }
}

/// Decides whether the morning utterance means "awake".
protocol WakeJudge {
    /// - clarity: on-device recognizer confidence for the phrase (0…1)
    /// - heardPhrase: did on-device recognition hear exactly "I'm awake"?
    /// - morningAudio: the clip, for Gemini (nil → cloud can't be used)
    func judge(clarity: Double, heardPhrase: Bool, morningAudio: Data?) async -> WakeDecision
}

enum WakeThresholds {
    static let acceptLocally = 0.80   // clear enough → awake without asking Gemini
    static let acceptOffline = 0.65   // offline, no LLM backup → lower bar to still let you up
}

// MARK: - Cloud judge (swappable: direct-to-Gemini, or a hosted proxy)

/// A cloud call that judges one clip. Implemented by `GeminiDirectJudge` (default) or
/// `GeminiWakeJudge` (optional backend proxy — kept for if you ever go public).
protocol CloudWakeJudging {
    func judge(morningAudio: Data, heardPhrase: Bool, localClarity: Double) async throws -> WakeDecision
}

// MARK: - Optional hosted proxy (unused on the direct path)

struct GeminiWakeJudge: CloudWakeJudging {
    let backendURL: URL
    let sharedSecret: String
    var timeout: TimeInterval = 8

    struct Unavailable: Error {}

    func judge(morningAudio: Data, heardPhrase: Bool, localClarity: Double) async throws -> WakeDecision {
        var req = URLRequest(url: backendURL.appendingPathComponent("judge"))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(sharedSecret)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "morning_audio_b64": morningAudio.base64EncodedString(),
            "audio_mime": "audio/mp4",
            "heard_phrase": heardPhrase,
            "local_clarity": localClarity,
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let isAwake = json["is_awake"] as? Bool
        else { throw Unavailable() }

        return WakeDecision(isAwake: isAwake,
                            clarity: localClarity,
                            confidence: (json["awake_confidence"] as? Double) ?? localClarity,
                            heardPhrase: (json["said_wake_phrase"] as? Bool) ?? heardPhrase,
                            reasoning: (json["reasoning"] as? String) ?? "Judged by Gemini.",
                            source: .gemini)
    }
}

// MARK: - Resilient (local-first, Gemini when unsure) — the one the app uses

struct ResilientWakeJudge: WakeJudge {
    let cloud: (any CloudWakeJudging)?   // nil when cloud judging is off

    func judge(clarity: Double, heardPhrase: Bool, morningAudio: Data?) async -> WakeDecision {
        // Must have said the phrase at all.
        guard heardPhrase else {
            return WakeDecision(isAwake: false, clarity: clarity, confidence: clarity,
                                heardPhrase: false,
                                reasoning: "Didn’t catch a clear “I’m awake”.", source: .local)
        }
        // Clearly spoken → accept on-device, no LLM call.
        if clarity >= WakeThresholds.acceptLocally {
            return WakeDecision(isAwake: true, clarity: clarity, confidence: clarity,
                                heardPhrase: true,
                                reasoning: "Clear “I’m awake”.", source: .local)
        }
        // Uncertain → ask Gemini if we can reach it.
        if let cloud, let audio = morningAudio {
            if let v = try? await cloud.judge(morningAudio: audio, heardPhrase: heardPhrase,
                                              localClarity: clarity) {
                return v
            }
            // Gemini unreachable → fall through to the offline bar.
        }
        let awake = clarity >= WakeThresholds.acceptOffline
        return WakeDecision(isAwake: awake, clarity: clarity, confidence: clarity, heardPhrase: true,
                            reasoning: awake ? "Cleared the on-device bar."
                                             : "Sounds slurred — you’re still half-asleep.",
                            source: .offline)
    }
}
