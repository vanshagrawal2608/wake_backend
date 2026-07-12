import Foundation

// MARK: - Deadline

/// What the user actually cares about: "be out of bed by …".
struct WakeDeadline: Codable, Equatable {
    /// Minutes from midnight (e.g. 8:50 = 530).
    var minutesFromMidnight: Int

    static let `default` = WakeDeadline(minutesFromMidnight: 8 * 60 + 50)

    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: minutesFromMidnight, to: start) ?? start
    }
}

// MARK: - Alarm

/// One scheduled wake-up. A person can have several (e.g. a morning and an evening one).
struct Alarm: Identifiable, Codable, Equatable {
    var id = UUID()
    var deadline: WakeDeadline
    var label: String
    var isEnabled: Bool = true

    static func new(hour: Int = 7, minute: Int = 0, label: String = "Alarm") -> Alarm {
        Alarm(deadline: WakeDeadline(minutesFromMidnight: hour * 60 + minute), label: label)
    }
}

// MARK: - Stages

/// One rung of the escalation ladder. `intensity` 0…1 drives both sound and colour.
struct WakeStage: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let detail: String
    /// Offset in minutes from the *start* of the wake window.
    let offsetMinutes: Int
    /// 0 (almost silent) … 1 (maximum).
    let intensity: Double
    let sound: Soundscape

    enum Soundscape: String, Codable, CaseIterable {
        case birdsong, rain, ambient, chime, alarmSoft, alarmFull, emergency
    }
}

extension WakeStage {
    /// The seven-rung ladder. Timings are *scaled* to the predicted window;
    /// offsets here are the canonical shape for a 26-minute window.
    static let ladder: [WakeStage] = [
        .init(id: 0, name: "Soft",          detail: "birdsong · rain",        offsetMinutes: 0,  intensity: 0.02, sound: .birdsong),
        .init(id: 1, name: "Gentle music",  detail: "ambient track, low",     offsetMinutes: 7,  intensity: 0.18, sound: .ambient),
        .init(id: 2, name: "Light + hum",   detail: "screen glows · soft buzz", offsetMinutes: 14, intensity: 0.38, sound: .ambient),
        .init(id: 3, name: "Notification",  detail: "louder music · vibration", offsetMinutes: 19, intensity: 0.58, sound: .chime),
        .init(id: 4, name: "Alarm",         detail: "clear alarm tone",       offsetMinutes: 23, intensity: 0.74, sound: .alarmSoft),
        .init(id: 5, name: "Louder alarm",  detail: "rising volume",          offsetMinutes: 25, intensity: 0.9,  sound: .alarmFull),
        .init(id: 6, name: "Emergency",     detail: "maximum · deadline",     offsetMinutes: 26, intensity: 1.0,  sound: .emergency),
    ]
}

// MARK: - Plan

/// A concrete, timed plan produced by the prediction engine for a given morning.
struct WakePlan: Codable, Equatable {
    let deadline: Date
    let windowMinutes: Int
    /// Absolute fire times per stage, already scaled to `windowMinutes`.
    let stageTimes: [Date]
    let stages: [WakeStage]

    var windowStart: Date { stageTimes.first ?? deadline }
}

// MARK: - Sleep

struct SleepEstimate: Codable, Equatable {
    let sleepStart: Date
    let confidence: Double          // 0…1
    let signals: [SleepSignal]
}

/// Extensible — new inputs (Watch, calendar, weather) add cases without breaking callers.
enum SleepSignal: String, Codable, CaseIterable {
    case inactivity, charging, screenLock, focusMode, healthKit, watch, motion
}

// MARK: - The learning record

/// Everything we store about one morning — the raw material for the model.
struct WakeRecord: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var sleepStart: Date?
    var deadline: Date
    var windowStart: Date          // when the first disturbance began
    var firstStageFired: Date?
    var dismissed: Date?           // when the user confirmed awake
    var phonePickedUp: Date?
    var firstUnlock: Date?
    var leftBed: Date?
    var stepsAtWake: Int?
    var snoozeEquivalents: Int      // "still waking up" taps, not 9-min snoozes
    var voiceConfirmed: Bool

    /// The label the model actually learns: minutes of disturbance needed.
    var wakeDurationMinutes: Double? {
        guard let dismissed else { return nil }
        return dismissed.timeIntervalSince(windowStart) / 60
    }

    var sleepDurationHours: Double? {
        guard let sleepStart, let dismissed else { return nil }
        return dismissed.timeIntervalSince(sleepStart) / 3600
    }
}

// MARK: - Onboarding personalization

/// How quickly the user wakes after the alarm — asked once at onboarding. It seeds
/// the initial wake-window length before there's enough history to learn from.
enum WakeSpeed: String, Codable, CaseIterable {
    case immediate      // up at the first sound
    case gradual        // needs a few minutes to surface
    case manyAlarms     // fights it — needs 4–5 escalations

    var coldStartMinutes: Double {
        switch self {
        case .immediate:  return 12
        case .gradual:    return 26
        case .manyAlarms: return 42
        }
    }
}

// MARK: - Prediction inputs (architecture for the future model)

/// Carries every signal the future CoreML model may use. Only a few are consumed today.
struct PredictionInputs: Codable {
    var isWeekend: Bool
    var priorSleepHours: Double?
    var sleepDebtHours: Double?
    var screenMinutesBeforeBed: Double?
    var wasCharging: Bool?
    var recentWakeDurations: [Double]   // most-recent-last
    // Future: motion, HealthKit HRV, watch, calendar first-event, weather…
}
