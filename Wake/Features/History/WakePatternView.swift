import SwiftUI
import Charts

/// Your wake-up pattern across recent mornings — how long you take to wake, when you
/// actually get up, and how consistent it is.
struct WakePatternView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var records: [WakeRecord] {
        app.records.filter { $0.dismissed != nil }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("How you wake, across your recent mornings.")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)

                    HStack(spacing: 12) {
                        tile("\(Int(app.stats.averageWakeDuration)) min", "Avg wake")
                        tile(typicalWakeTime, "Typical up")
                        tile(consistency, "Consistency")
                    }

                    WakeCard {
                        VStack(alignment: .leading, spacing: 10) {
                            MicroLabel(text: "Wake duration per morning")
                            Chart(records) { r in
                                BarMark(x: .value("Day", r.date, unit: .day),
                                        y: .value("Minutes", r.wakeDurationMinutes ?? 0))
                                    .foregroundStyle(Theme.intensity(min((r.wakeDurationMinutes ?? 0) / 45, 1)))
                                    .cornerRadius(4)
                            }
                            .frame(height: 180)
                            .chartYAxis { AxisMarks(position: .leading) }
                        }
                    }

                    WakeCard {
                        VStack(alignment: .leading, spacing: 10) {
                            MicroLabel(text: "Time you got out of bed")
                            Chart(records) { r in
                                if let d = r.dismissed {
                                    LineMark(x: .value("Day", r.date, unit: .day),
                                             y: .value("Minute of day", minutesOfDay(d)))
                                        .foregroundStyle(Theme.i1)
                                    PointMark(x: .value("Day", r.date, unit: .day),
                                              y: .value("Minute of day", minutesOfDay(d)))
                                        .foregroundStyle(Theme.i2)
                                }
                            }
                            .frame(height: 150)
                        }
                    }
                }
                .padding(20)
            }
            .background(NightBackground())
            .navigationTitle("Wake pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }

    private func tile(_ value: String, _ key: String) -> some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.system(size: 20, weight: .heavy)).monospacedDigit()
                Text(key.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func minutesOfDay(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
    private var typicalWakeTime: String {
        let mins = records.compactMap { $0.dismissed.map(minutesOfDay) }
        guard !mins.isEmpty else { return "—" }
        let avg = Int(mins.reduce(0, +) / Double(mins.count))
        let h = (avg / 60) % 12 == 0 ? 12 : (avg / 60) % 12
        return String(format: "%d:%02d", h, avg % 60)
    }
    private var consistency: String {
        let mins = records.compactMap { $0.dismissed.map(minutesOfDay) }
        guard mins.count > 1 else { return "—" }
        let avg = mins.reduce(0, +) / Double(mins.count)
        let variance = mins.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(mins.count)
        return "±\(Int(variance.squareRoot())) min"
    }
}
