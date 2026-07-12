import Foundation
#if canImport(HealthKit)
import HealthKit
#endif
#if canImport(CoreMotion)
import CoreMotion
#endif

/// Infers when the user fell asleep from iOS data — no "I'm going to bed" button and
/// no overnight background loop (iOS won't allow one). The strategy is retrospective:
/// each morning we *reconcile* the real sleep-start by querying history.
///
/// Fusion order (iPhone-only, no Apple Watch): HealthKit if any sleep data exists →
/// Core Motion's long overnight stationary block → the live inactivity prior.
protocol SleepDetecting {
    func requestAuthorization() async
    /// Best-effort authoritative sleep start for the night before `day`.
    func reconcile(for day: Date) async -> SleepEstimate?
}

final class SleepDetector: SleepDetecting {
    /// Weak live prior, captured whenever the app is briefly alive (charging/lock/last-use).
    var snapshotProvider: () -> Snapshot = {
        Snapshot(lastInteraction: .now, isCharging: false, isLocked: false, focusSleepActive: false)
    }
    struct Snapshot {
        var lastInteraction: Date
        var isCharging: Bool
        var isLocked: Bool
        var focusSleepActive: Bool
    }

    #if canImport(CoreMotion)
    private let motion = CMMotionActivityManager()
    #endif

    // MARK: - Authorization

    func requestAuthorization() async {
        #if canImport(HealthKit)
        if HKHealthStore.isHealthDataAvailable(),
           let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            try? await HKHealthStore().requestAuthorization(toShare: [], read: [sleepType])
        }
        #endif
        // Core Motion auth is requested implicitly on first query; the permission prompt
        // is driven by NSMotionUsageDescription.
    }

    // MARK: - Morning reconciliation (the accurate path)

    func reconcile(for day: Date = .now) async -> SleepEstimate? {
        if let hk = await healthKitSleepStart(for: day) {
            return SleepEstimate(sleepStart: hk, confidence: 0.95, signals: [.healthKit])
        }
        if let onset = await motionSleepOnset(for: day) {
            return SleepEstimate(sleepStart: onset, confidence: 0.7, signals: [.motion, .inactivity])
        }
        return livePrior()
    }

    /// A cheap fallback from whatever we last observed while awake.
    private func livePrior() -> SleepEstimate? {
        let s = snapshotProvider()
        var signals: [SleepSignal] = []
        var confidence = 0.0
        if Date.now.timeIntervalSince(s.lastInteraction) > 20 * 60 { signals.append(.inactivity); confidence += 0.2 }
        if s.isCharging { signals.append(.charging); confidence += 0.1 }
        if s.isLocked { signals.append(.screenLock); confidence += 0.05 }
        if s.focusSleepActive { signals.append(.focusMode); confidence += 0.15 }
        guard confidence >= 0.3 else { return nil }
        return SleepEstimate(sleepStart: s.lastInteraction, confidence: min(confidence, 0.5), signals: signals)
    }

    // MARK: - Core Motion: longest overnight stationary block

    /// Queries last night's motion history and returns the start of the longest
    /// continuous high-confidence stationary span — a good proxy for sleep onset when
    /// there's no Watch/HealthKit data. Motion history is retained ~7 days on-device.
    private func motionSleepOnset(for day: Date, calendar: Calendar = .current) async -> Date? {
        #if canImport(CoreMotion)
        guard CMMotionActivityManager.isActivityAvailable() else { return nil }

        // Night window: previous evening 20:00 → this morning 11:00.
        let morning = calendar.startOfDay(for: day).addingTimeInterval(11 * 3600)
        let start = calendar.startOfDay(for: day).addingTimeInterval(-4 * 3600)   // prev day 20:00

        let activities: [CMMotionActivity] = await withCheckedContinuation { cont in
            motion.queryActivityStarting(from: start, to: morning, to: OperationQueue()) { acts, _ in
                cont.resume(returning: acts ?? [])
            }
        }
        guard !activities.isEmpty else { return nil }

        // Walk segments; each spans from its startDate to the next segment's start.
        // Group contiguous stationary segments into runs, track the longest.
        var bestStart: Date?
        var bestDuration: TimeInterval = 0
        var runStart: Date?
        for (i, act) in activities.enumerated() {
            let segEnd = (i + 1 < activities.count) ? activities[i + 1].startDate : morning
            let asleepish = act.stationary && !act.automotive && act.confidence != .low
            if asleepish {
                if runStart == nil { runStart = act.startDate }
                if let rs = runStart {
                    let dur = segEnd.timeIntervalSince(rs)
                    if dur > bestDuration { bestDuration = dur; bestStart = rs }
                }
            } else {
                runStart = nil
            }
        }
        // Only trust a genuinely sleep-sized block (≥ 3h), else it's just "phone on desk".
        return bestDuration >= 3 * 3600 ? bestStart : nil
        #else
        return nil
        #endif
    }

    // MARK: - HealthKit: authoritative when present

    private func healthKitSleepStart(for day: Date, calendar: Calendar = .current) async -> Date? {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)
        else { return nil }
        let store = HKHealthStore()

        let morning = calendar.startOfDay(for: day).addingTimeInterval(12 * 3600)
        let start = morning.addingTimeInterval(-24 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: morning)

        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        return samples.first(where: { asleepValues.contains($0.value) })?.startDate
        #else
        return nil
        #endif
    }
}
