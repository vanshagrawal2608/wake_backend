import SwiftUI

/// "History" — the last two mornings and how the plan played out. Wake keeps only a
/// short context window (recent behaviour is weighted highest when planning tomorrow).
struct HistoryView: View {
    @Environment(AppState.self) private var app

    /// Most recent first, capped at 2.
    private var recent: [WakeRecord] {
        Array(app.records.sorted { $0.date > $1.date }.prefix(2))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your last two mornings, and how the plan played out.")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)

                    ForEach(recent) { rec in card(rec) }

                    Text("Wake keeps only your last 2 mornings in context — recent behaviour is weighted highest when planning tomorrow.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.faint).padding(.top, 4)
                }
                .padding(20)
            }
            .background(NightBackground())
            .navigationTitle("History")
        }
    }

    private func card(_ rec: WakeRecord) -> some View {
        let delta = rec.dismissed.map { $0.timeIntervalSince(rec.deadline) / 60 } ?? 0   // minutes vs deadline
        let early = delta <= 0
        return WakeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DayFmt.relative(rec.date)).font(.system(size: 15, weight: .heavy))
                        Text("Deadline \(TimeFmt.clock(rec.deadline))")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    outcomePill(minutes: delta, early: early)
                }
                HStack(spacing: 16) {
                    stat("\(Int(rec.wakeDurationMinutes ?? 0)) min", "Wake dur.")
                    stat("\(rec.snoozeEquivalents)×", "“still waking”")
                    if let d = rec.dismissed { stat(TimeFmt.clock(d), "Out of bed") }
                    stat(rec.voiceConfirmed ? "Voice" : "—", "Confirmed")
                }
            }
        }
    }

    private func outcomePill(minutes: Double, early: Bool) -> some View {
        let mins = abs(Int(minutes.rounded()))
        return Text(early ? "Up \(mins) min early" : "Up \(mins) min late")
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(early ? Theme.good : Theme.i2)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background((early ? Theme.good : Theme.i2).opacity(0.15), in: Capsule())
    }

    private func stat(_ value: String, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 18, weight: .heavy)).monospacedDigit()
            Text(key.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.8)
                .foregroundStyle(Theme.faint)
        }
    }
}

enum DayFmt {
    static func relative(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f.string(from: date)
    }
}
