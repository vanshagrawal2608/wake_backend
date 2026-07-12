import Foundation

/// Turns history into a concrete, timed plan for a given deadline.
/// Today: recency-weighted average of past wake durations. Tomorrow: CoreML,
/// swapped in behind `WakeDurationModel` without changing this type's callers.
protocol WakeDurationModel {
    /// Predicted minutes of disturbance the user needs, given inputs.
    func predictWakeDuration(_ inputs: PredictionInputs) -> Double
}

/// The initial, transparent heuristic model.
struct HeuristicWakeDurationModel: WakeDurationModel {
    /// Sensible default before we have data.
    var coldStart: Double = 26
    /// Bounds so a weird morning can't produce a 3-min or 90-min window.
    var range: ClosedRange<Double> = 12...45

    func predictWakeDuration(_ inputs: PredictionInputs) -> Double {
        var base = coldStart
        if !inputs.recentWakeDurations.isEmpty {
            // Exponential recency weighting: newer mornings count more.
            var weightSum = 0.0, acc = 0.0, w = 1.0
            for d in inputs.recentWakeDurations.reversed() {   // newest first
                acc += d * w; weightSum += w; w *= 0.82
            }
            base = acc / weightSum
        }
        // Cheap, explainable adjustments the future model will learn instead.
        if inputs.isWeekend { base += 4 }
        if let debt = inputs.sleepDebtHours, debt > 1 { base += min(debt * 1.5, 8) }
        if let screen = inputs.screenMinutesBeforeBed, screen > 45 { base += 5 }
        return min(max(base, range.lowerBound), range.upperBound)
    }
}

struct WakePredictionEngine {
    var model: WakeDurationModel = HeuristicWakeDurationModel()

    func plan(deadline: WakeDeadline,
              on day: Date = .now,
              inputs: PredictionInputs,
              calendar: Calendar = .current) -> WakePlan {
        let deadlineDate = deadline.date(on: day, calendar: calendar)
        let window = model.predictWakeDuration(inputs)
        let start = deadlineDate.addingTimeInterval(-window * 60)

        // Scale the canonical 26-min ladder onto the predicted window.
        let canonical = 26.0
        let stages = WakeStage.ladder
        let times = stages.map { stage -> Date in
            let scaled = Double(stage.offsetMinutes) / canonical * window
            return start.addingTimeInterval(scaled * 60)
        }
        return WakePlan(deadline: deadlineDate,
                        windowMinutes: Int(window.rounded()),
                        stageTimes: times,
                        stages: stages)
    }
}

/// The learning loop: after each morning, feed the record back so tomorrow improves.
struct LearningEngine {
    let store: WakeStore

    func inputs(for day: Date = .now, calendar: Calendar = .current) -> PredictionInputs {
        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = weekday == 1 || weekday == 7
        return PredictionInputs(
            isWeekend: isWeekend,
            priorSleepHours: store.records.last?.sleepDurationHours,
            sleepDebtHours: sleepDebt(),
            screenMinutesBeforeBed: nil,          // TODO(device): DeviceActivity
            wasCharging: nil,
            recentWakeDurations: store.recentWakeDurations()
        )
    }

    /// Simple 7-day debt vs an 8h target — placeholder for a richer model.
    private func sleepDebt() -> Double? {
        let recent = store.records.suffix(7).compactMap(\.sleepDurationHours)
        guard !recent.isEmpty else { return nil }
        let avg = recent.reduce(0, +) / Double(recent.count)
        return max(0, 8 - avg)
    }
}
