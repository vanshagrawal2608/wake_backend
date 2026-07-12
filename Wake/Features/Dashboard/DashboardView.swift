import SwiftUI

/// "Insights" — Apple-Health-style rings, sparkline and learned insights.
struct DashboardView: View {
    @Environment(AppState.self) private var app
    private var stats: WakeStats { app.stats }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("This week · \(stats.records.count) mornings")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                    accuracyCard
                    HStack(spacing: 12) {
                        statTile("Avg wake duration", "\(Int(stats.averageWakeDuration))", "min")
                        statTile("Avg sleep", TimeFmt.clock(hoursToDate(stats.averageSleepHours)), "")
                    }
                    trendCard
                    learnedCard
                }
                .padding(20)
            }
            .background(NightBackground())
            .navigationTitle("Insights")
        }
    }

    private var accuracyCard: some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 12) {
                MicroLabel(text: "Wake accuracy")
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.09), lineWidth: 9)
                        Circle().trim(from: 0, to: stats.accuracy)
                            .stroke(Theme.good, style: .init(lineWidth: 9, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(stats.accuracy * 100))%")
                            .font(.system(size: 40, weight: .heavy)).monospacedDigit()
                        Text("up on the deadline within ±3 min")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    private func statTile(_ label: String, _ value: String, _ unit: String) -> some View {
        WakeCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel(text: label)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 26, weight: .heavy)).monospacedDigit()
                    Text(unit).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private var trendCard: some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel(text: "Wake duration trend")
                Sparkline(values: stats.wakeDurationTrend)
                    .frame(height: 64)
                HStack { Text("Mon"); Spacer(); Text("Sun") }
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
            }
        }
    }

    private var learnedCard: some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 0) {
                MicroLabel(text: "What Wake learned")
                    .padding(.bottom, 6)
                insight("moon.stars", "Weekends run 11 min longer.", "Wake starts your Saturday window earlier automatically.")
                insight("iphone", "Late screen time slows you down.", "Nights past 1am added ~7 min of wake latency.")
                insight("mic.fill", "Voice confirms best around stage 4.", "You rarely truly wake before then — so it holds back sound until then.")
            }
        }
    }

    private func insight(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Theme.i0.opacity(0.16), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(Theme.i0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(body).font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, 13)
        .overlay(Divider().background(Theme.hair), alignment: .top)
    }

    private func hoursToDate(_ h: Double) -> Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: Int(h), minute: Int((h - Double(Int(h))) * 60), second: 0, of: .now) ?? .now
    }
}

/// Minimal area sparkline with an emphasised endpoint.
struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let vals = values.isEmpty ? [26,24,29,26,33,28,26] : values
            let maxV = (vals.max() ?? 1), minV = (vals.min() ?? 0)
            let range = max(maxV - minV, 1)
            let pts = vals.enumerated().map { i, v -> CGPoint in
                let x = geo.size.width * CGFloat(i) / CGFloat(max(vals.count - 1, 1))
                let y = geo.size.height * (1 - CGFloat((v - minV) / range)) * 0.8 + geo.size.height * 0.1
                return CGPoint(x: x, y: y)
            }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                }
                .fill(LinearGradient(colors: [Theme.i0.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(Theme.i0, style: .init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle().fill(Theme.i0).frame(width: 8, height: 8).position(last)
                }
            }
        }
    }
}
