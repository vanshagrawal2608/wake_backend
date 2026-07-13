import Foundation
import Observation

/// Single source of truth. Owns the services and exposes just what the UI needs.
@Observable
final class AppState {
    // The user's alarms (a person can have several — e.g. morning + evening).
    private(set) var alarms: [Alarm]

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
        self.learning = LearningEngine(store: store)
        self.scheduler = scheduler
        self.voice = voice

        // Seed the prediction model's cold-start from the persisted wake-speed, using
        // locals so we don't touch `self` before every stored property is initialized.
        let speed = WakeSpeed(rawValue: UserDefaults.standard.string(forKey: "wake.speed") ?? "") ?? .gradual
        var engine = prediction
        engine.model = HeuristicWakeDurationModel(coldStart: speed.coldStartMinutes)
        self.prediction = engine
        self.alarms = AppState.loadAlarms() ?? [Alarm(deadline: .default, label: "Morning")]
    }

    // MARK: - Plans

    /// The timed wake plan for a given alarm (sunrise curve + stages).
    func plan(for alarm: Alarm) -> WakePlan {
        prediction.plan(deadline: alarm.deadline, inputs: learning.inputs())
    }

    /// The soonest enabled alarm — what the live wake experience targets.
    var nextAlarm: Alarm? {
        alarms.filter(\.isEnabled).min { $0.deadline.minutesFromMidnight < $1.deadline.minutesFromMidnight }
    }
    var currentPlan: WakePlan {
        plan(for: nextAlarm ?? alarms.first ?? Alarm(deadline: .default, label: "Alarm"))
    }

    // MARK: - Alarm CRUD

    func addAlarm(deadline: WakeDeadline, label: String) {
        alarms.append(Alarm(deadline: deadline, label: label.isEmpty ? "Alarm" : label))
        saveAlarms()
    }
    func deleteAlarm(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }; saveAlarms()
    }
    func update(_ alarm: Alarm) {
        guard let i = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        alarms[i] = alarm; saveAlarms()
    }

    private static let alarmsKey = "wake.alarms"
    private func saveAlarms() {
        if let data = try? JSONEncoder.wake.encode(alarms) {
            UserDefaults.standard.set(data, forKey: AppState.alarmsKey)
        }
    }
    private static func loadAlarms() -> [Alarm]? {
        guard let data = UserDefaults.standard.data(forKey: alarmsKey),
              let a = try? JSONDecoder.wake.decode([Alarm].self, from: data), !a.isEmpty
        else { return nil }
        return a
    }

    /// Reconcile last night's sleep start from iOS history (call each morning / on open).
    /// TODO(device): stamp the result onto the morning's WakeRecord so the learning
    /// engine's sleep-duration + sleep-debt inputs reflect it.
    @MainActor func refreshSleep() async {
        await sleep.requestAuthorization()
        lastSleepEstimate = await sleep.reconcile(for: .now)
    }

    /// Finish onboarding: create the first alarm + set the wake-speed that seeds plans.
    func completeOnboarding(deadline: WakeDeadline, wakeSpeed: WakeSpeed) {
        self.wakeSpeed = wakeSpeed
        UserDefaults.standard.set(wakeSpeed.rawValue, forKey: "wake.speed")
        hasOnboarded = true
        prediction.model = HeuristicWakeDurationModel(coldStart: wakeSpeed.coldStartMinutes)
        alarms = [Alarm(deadline: deadline, label: "Morning")]
        saveAlarms()
    }

    /// Advance the live soundscape to a stage's intensity (the audible ramp layer).
    /// Uses the alarm's imported audio (voice/music) if set, else the default tone.
    func enterStage(_ index: Int) {
        let stages = currentPlan.stages
        guard stages.indices.contains(index) else { return }
        let intensity = stages[index].intensity
        if let alarm = nextAlarm, let url = audioURL(for: alarm) {
            audio.playCustom(url: url, targetIntensity: intensity)
        } else {
            audio.play(soundscape: stages[index].sound, targetIntensity: intensity)
        }
    }

    // MARK: - Custom alarm audio (import a voice/music clip per alarm)

    static var soundsDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlarmSounds")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func audioURL(for alarm: Alarm) -> URL? {
        guard let name = alarm.customAudioFilename else { return nil }
        let url = AppState.soundsDir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Copy a picked audio file into the app's sounds folder and attach it to the alarm.
    func setAudio(from pickedURL: URL, for alarm: Alarm) {
        let scoped = pickedURL.startAccessingSecurityScopedResource()
        defer { if scoped { pickedURL.stopAccessingSecurityScopedResource() } }
        let filename = "\(UUID().uuidString)-\(pickedURL.lastPathComponent)"
        let dest = AppState.soundsDir.appendingPathComponent(filename)
        guard (try? FileManager.default.copyItem(at: pickedURL, to: dest)) != nil else { return }
        var a = alarm; a.customAudioFilename = filename; update(a)
    }

    func clearAudio(for alarm: Alarm) {
        if let url = audioURL(for: alarm) { try? FileManager.default.removeItem(at: url) }
        var a = alarm; a.customAudioFilename = nil; update(a)
    }

    /// Decide whether the morning utterance means "awake" — local clarity first,
    /// Gemini when unsure (single clip, no baseline). Never blocks: offline falls back.
    func judgeAwake(clarity: Double, heardPhrase: Bool, morningAudio: Data?) async -> WakeDecision {
        await judge.judge(clarity: clarity, heardPhrase: heardPhrase, morningAudio: morningAudio)
    }

    /// Confirmed awake — stop everything.
    func confirmAwake() {
        audio.stop()
        scheduler.cancelAll()
        voice.stop()
    }

    // MARK: - Stats (feeds Insights)

    var stats: WakeStats { WakeStats(records: store.records) }
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
