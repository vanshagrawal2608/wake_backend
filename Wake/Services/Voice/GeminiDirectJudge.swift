import Foundation

/// Calls Gemini 2.5 Flash **directly** from the app (no backend). The API key lives
/// in the app — fine for your own + trusted devices, protected by a budget cap in
/// Google AI Studio. Audio-native: sends the raw clip, gets a JSON verdict.
struct GeminiDirectJudge: CloudWakeJudging {
    let apiKey: String
    var model = "gemini-flash-latest"
    var timeout: TimeInterval = 8

    struct Unavailable: Error {}

    func judge(morningAudio: Data, heardPhrase: Bool, localClarity: Double) async throws -> WakeDecision {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { throw Unavailable() }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Gemini responseSchema uses uppercase OpenAPI-style type names.
        let schema: [String: Any] = [
            "type": "OBJECT",
            "properties": [
                "heard_text": ["type": "STRING"],
                "said_wake_phrase": ["type": "BOOLEAN"],
                "is_awake": ["type": "BOOLEAN"],
                "awake_confidence": ["type": "NUMBER"],
                "sounds_groggy": ["type": "BOOLEAN"],
                "reasoning": ["type": "STRING"],
            ],
            "required": ["heard_text", "said_wake_phrase", "is_awake",
                         "awake_confidence", "sounds_groggy", "reasoning"],
        ]
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": Self.instruction]]],
            "contents": [[
                "role": "user",
                "parts": [
                    ["inlineData": ["mimeType": "audio/mp4", "data": morningAudio.base64EncodedString()]],
                    ["text": "On-device recognizer heard 'I'm awake': \(heardPhrase). Local clarity \(String(format: "%.2f", localClarity)) (uncertain). Judge the recording."],
                ],
            ]],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
                "temperature": 0,
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String,
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let isAwake = json["is_awake"] as? Bool
        else { throw Unavailable() }

        return WakeDecision(isAwake: isAwake,
                            clarity: localClarity,
                            confidence: (json["awake_confidence"] as? Double) ?? localClarity,
                            heardPhrase: (json["said_wake_phrase"] as? Bool) ?? heardPhrase,
                            reasoning: (json["reasoning"] as? String) ?? "Judged by Gemini.",
                            source: .gemini)
    }

    static let instruction = """
    You judge whether a person is awake from ONE short recording in which they were asked to say "I'm awake".
    STEP 1 — Transcribe the clip into heard_text. It must be the wake phrase "I'm awake" (accept 'im awake' / 'i am awake'). If it says anything else, or is mumbled past recognition, set said_wake_phrase=false, is_awake=false, and stop.
    STEP 2 — Only if they said the phrase, judge how AWAKE they sound. There is NO personal baseline, so judge in absolute terms: a clear, promptly and crisply spoken "I'm awake" means awake; a slurred, mumbled, dragging, hesitant, or half-swallowed one means groggy. Err toward NOT awake when unclear.
    is_awake is true ONLY when they clearly said "I'm awake" AND it sounds alert. awake_confidence is your 0..1 clarity/alertness rating. Keep reasoning to one short sentence a person could read on a lock screen.
    """
}
