import Foundation
import Observation

/// Single source of truth. Owns the services and exposes just what the UI needs.
@Observable
final class AppState {
    // Persisted user intent
    var deadline: WakeDeadline {
        didSet { recomputePlan() }
    }

    // Derived
    private(set) var plan: WakePlan
    var records: [WakeRecord] { store.records }

    // Live wake session (nil when not actively waking)
    var session: WakeSession?

    // Sleep detection (iPhone-only: HealthKit if present → Core Motion → live prior).
    let sleep: SleepDetecting = SleepDetector()
    private(set) var lastSleepEstimate: SleepEstimate?

    // Onboarding state (persisted).
    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "wake.onboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "wake.onboarded") }
    }
    private(set) var wakeSpeed: WakeSpeed = {
        WakeSpeed(rawValue: UserDefaults.standard.string(forKey: "wake.speed") ?? "") ?? .gradual
    }()

    // Services — protocol-typed so they're swappable.
    private let store: WakeStore
    private var prediction: WakePredictionEngine
    private let learning: LearningEngine
    private let scheduler: AlarmScheduling
    let voice: VoiceWakeVerifying
    let audio = AudioRampPlayer()
    /// Local-first (Gemini when unsure) awake/not-awake decision — no baseline.
    let judge: WakeJudge = Config.makeJudge()

    init(store: WakeStore = WakeStore(),
         prediction: WakePredictionEngine = WakePredictionEngine(),
         scheduler: AlarmScheduling = AlarmKitScheduler(),
         voice: VoiceWakeVerifying = VoiceWakeVerifier()) {
        self.store = store
        self.prediction = prediction
        self.learning = LearningEngine(store: store)
        self.scheduler = scheduler
        self.voice = voice
        self.deadline = .default
        // Seed the prediction model's cold-start from the onboarding wake-speed.
        self.prediction.model = HeuristicWakeDurationModel(coldStart: wakeSpeed.coldStartMinutes)
        // Seed plan
        self.plan = self.prediction.plan(deadline: .default,
                                         inputs: LearningEngine(store: store).inputs())
    }

    func recomputePlan() {
        plan = prediction.plan(deadline: deadline, inputs: learning.inputs())
    }

    /// Reconcile last night's sleep start from iOS history (call each morning / on open).
    /// TODO(device): stamp the result onto the morning's WakeRecord so the learning
    /// engine's sleep-duration + sleep-debt inputs reflect it.
    @MainActor func refreshSleep() async {
        await sleep.requestAuthorization()
        lastSleepEstimate = await sleep.reconcile(for: .now)
    }

    func nudgeDeadline(minutes: Int) {
        deadline.minutesFromMidnight += minutes
    }

    /// Finish onboarding: set the deadline and the wake-speed that seeds the first plan.
    func completeOnboarding(deadline: WakeDeadline, wakeSpeed: WakeSpeed) {
        self.deadline = deadline
        self.wakeSpeed = wakeSpeed
        UserDefaults.standard.set(wakeSpeed.rawValue, forKey: "wake.speed")
        hasOnboarded = true
        prediction.model = HeuristicWakeDurationModel(coldStart: wakeSpeed.coldStartMinutes)
        recomputePlan()
    }

    /// Advance the live soundscape to a stage's intensity (the audible ramp layer).
    func enterStage(_ index: Int) {
        guard plan.stages.indices.contains(index) else { return }
        let stage = plan.stages[index]
        audio.play(soundscape: stage.sound, targetIntensity: stage.intensity)
    }

    /// Decide whether the morning utterance means "awake" — local clarity first,
    /// Gemini when unsure (single clip, no baseline). Never blocks: offline falls back.
    func judgeAwake(clarity: Double, heardPhrase: Bool, morningAudio: Data?) async -> WakeDecision {
        await judge.judge(clarity: clarity, heardPhrase: heardPhrase, morningAudio: morningAudio)
    }

    /// Warm the free-tier backend before the user speaks, so the /judge call isn't a
    /// 30–60s cold start at 6am. Fire this when the wake sequence begins.
    func prewarmJudge() async {
        guard Config.cloudMatchEnabled, let url = Config.matchBackendURL else { return }
        _ = try? await URLSession.shared.data(from: url.appendingPathComponent("healthz"))
    }

    /// Confirmed awake — stop everything.
    func confirmAwake() {
        audio.stop()
        scheduler.cancelAll()
        voice.stop()
    }

    /// Arm tonight's alarm ladder.
    func arm() {
        recomputePlan()
        Task {
            await scheduler.requestAuthorization()
            await scheduler.schedule(plan)
        }
    }

    // MARK: - Stats (feeds Insights)

    var stats: WakeStats { WakeStats(records: store.records, deadline: deadline) }
}

/// Live morning session — drives the Wake screen.
struct WakeSession {
    var plan: WakePlan
    var currentStageIndex: Int
    var voiceState: VoiceFeedback = .idle

    enum VoiceFeedback: Equatable {
        case idle, listening
        case awake                 // confirmed, alarm stopped
        case groggy                // heard, but doesn't sound awake
    }
}

/// Rolled-up statistics for the dashboard.
struct WakeStats {
    let records: [WakeRecord]
    let deadline: WakeDeadline

    var averageWakeDuration: Double {
        let d = records.compactMap(\.wakeDurationMinutes)
        return d.isEmpty ? 26 : d.reduce(0,+) / Double(d.count)
    }
    var averageSleepHours: Double {
        let d = records.compactMap(\.sleepDurationHours)
        return d.isEmpty ? 7.4 : d.reduce(0,+) / Double(d.count)
    }
    var averageSnoozes: Double {
        records.isEmpty ? 0 : Double(records.map(\.snoozeEquivalents).reduce(0,+)) / Double(records.count)
    }
    /// % of mornings the user was up within ±3 min of the deadline.
    var accuracy: Double {
        let judged = records.compactMap { r -> Bool? in
            guard let d = r.dismissed else { return nil }
            return abs(d.timeIntervalSince(r.deadline)) <= 180
        }
        guard !judged.isEmpty else { return 0 }
        return Double(judged.filter { $0 }.count) / Double(judged.count)
    }
    var wakeDurationTrend: [Double] {
        records.suffix(7).compactMap(\.wakeDurationMinutes)
    }
}
