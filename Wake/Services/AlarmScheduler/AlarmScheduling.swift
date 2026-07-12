import Foundation
import UserNotifications

/// Fires the escalation ladder. Protocol so we can start with notifications and
/// swap in AlarmKit (iOS 26) for the guaranteed, silent-mode-breaking deadline alarm.
protocol AlarmScheduling {
    func requestAuthorization() async
    /// Schedule the whole ladder for a plan. Returns identifiers we can cancel.
    func schedule(_ plan: WakePlan) async
    func cancelAll()
}

/// Today's implementation: a chain of pre-scheduled local notifications, one per
/// stage, marked time-sensitive so they surface through most Focus modes.
/// Works fully in the background — the reliable floor beneath the live audio ramp.
final class NotificationAlarmScheduler: AlarmScheduling {
    private let center = UNUserNotificationCenter.current()
    private let group = "wake.ladder"

    func requestAuthorization() async {
        // Free-signing friendly: no `.criticalAlert` (that needs a paid entitlement).
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(_ plan: WakePlan) async {
        cancelAll()
        for (stage, fire) in zip(plan.stages, plan.stageTimes) where fire > .now {
            let content = UNMutableNotificationContent()
            content.title = stage.name
            content.body = stage.detail
            // `.active`/`.timeSensitive` work without the paid Critical Alerts entitlement.
            content.interruptionLevel = stage.intensity >= 0.7 ? .timeSensitive : .active
            content.sound = sound(for: stage)
            content.threadIdentifier = group

            let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: "\(group).\(stage.id)", content: content, trigger: trigger)
            try? await center.add(req)
        }
    }

    func cancelAll() {
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.filter { $0.identifier.hasPrefix(self.group) }.map(\.identifier)
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func sound(for stage: WakeStage) -> UNNotificationSound {
        // TODO(device): ship bundled soundscape files (birdsong.caf, ambient.caf, …)
        // and return `UNNotificationSound(named:)`. `.default` needs no entitlement.
        .default
    }
}

/// iOS 26 seam. When available + entitled, AlarmKit gives a real alarm that
/// breaks through silent mode and Focus for the guaranteed deadline stage.
/// Left as a structured stub so the app builds on today's SDK.
final class AlarmKitScheduler: AlarmScheduling {
    private let fallback = NotificationAlarmScheduler()

    func requestAuthorization() async { await fallback.requestAuthorization() }

    func schedule(_ plan: WakePlan) async {
        // TODO(iOS26): use AlarmKit for the final guaranteed stage:
        //   let alarm = Alarm(...); try await AlarmManager.shared.schedule(alarm)
        // and let notifications drive the gentle early ladder.
        await fallback.schedule(plan)
    }

    func cancelAll() { fallback.cancelAll() }
}
