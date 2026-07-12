import Foundation

/// App configuration. Cloud judging (Gemini) is opt-in; the app works fully on-device
/// without it. The Gemini key is injected from a gitignored `Secrets.xcconfig` into
/// Info.plist as `WakeGeminiKey` — it is never committed.
enum Config {
    /// Your Gemini API key, injected at build time (empty → cloud judging disabled).
    /// Protect it with a spending cap in Google AI Studio.
    static var geminiKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "WakeGeminiKey") as? String) ?? ""
    }

    /// Whether to send the morning clip to Gemini when the on-device clarity check is
    /// uncertain. Persisted; toggled in Settings/onboarding.
    static var cloudMatchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "wake.cloudMatchEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "wake.cloudMatchEnabled") }
    }

    /// The wake judge the app should use, given current config + consent.
    static func makeJudge() -> WakeJudge {
        if cloudMatchEnabled, !geminiKey.isEmpty {
            return ResilientWakeJudge(cloud: GeminiDirectJudge(apiKey: geminiKey))
        }
        return ResilientWakeJudge(cloud: nil)   // on-device only, still resilient-shaped
    }
}
