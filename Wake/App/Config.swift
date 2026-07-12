import Foundation

/// App configuration. Cloud judging is opt-in and off by default; the app works fully
/// on-device without it.
enum Config {
    /// Your deployed backend proxy (see Wake/backend). nil → cloud judging disabled.
    /// Set to e.g. URL(string: "https://wake-judge.example.com").
    static let matchBackendURL: URL? = nil

    /// Whether the user has opted into sending the morning clip to Gemini when the
    /// on-device clarity check is uncertain. Persisted; toggled in Settings/onboarding.
    static var cloudMatchEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "wake.cloudMatchEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "wake.cloudMatchEnabled") }
    }

    /// Shared secret for the backend. TODO(security): store in Keychain and provision
    /// per-user auth before public release — this is a single shared token for TestFlight.
    static var backendSecret: String {
        (Bundle.main.object(forInfoDictionaryKey: "WakeBackendSecret") as? String) ?? ""
    }

    /// The wake judge the app should use, given current config + consent.
    static func makeJudge() -> WakeJudge {
        if cloudMatchEnabled, let url = matchBackendURL, !backendSecret.isEmpty {
            return ResilientWakeJudge(cloud: GeminiWakeJudge(backendURL: url, sharedSecret: backendSecret))
        }
        return ResilientWakeJudge(cloud: nil)   // on-device only, still resilient-shaped
    }
}
