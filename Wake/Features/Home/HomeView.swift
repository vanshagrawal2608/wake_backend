import SwiftUI

/// "Tonight" — set the deadline, see the predicted sunrise curve.
struct HomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    deadlineCard
                    if let est = app.lastSleepEstimate { sleepLine(est) }
                    curveCard
                    Text("Wake never jumps to maximum. It starts almost silent and climbs only as far as it needs to get you up.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(NightBackground())
            .navigationTitle("Tonight")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Arm") { app.arm() }.fontWeight(.semibold)
                }
            }
            .task { await app.refreshSleep() }        // reconcile last night's sleep on open
        }
    }

    /// Small row showing the sleep start iOS inferred, and from which signal.
    private func sleepLine(_ est: SleepEstimate) -> some View {
        let src = est.signals.contains(.healthKit) ? "Health"
                : est.signals.contains(.motion) ? "motion"
                : "estimate"
        return HStack(spacing: 8) {
            Image(systemName: "bed.double.fill").font(.system(size: 13))
            Text("Fell asleep ~\(TimeFmt.clock(est.sleepStart))")
                .font(.system(size: 13.5, weight: .semibold))
            Text("· \(src)").font(.system(size: 12)).foregroundStyle(Theme.faint)
            Spacer()
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 6)
    }

    private var header: some View {
        Text("You need to be out of bed by your deadline. Wake handles everything before it.")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.muted)
    }

    private var deadlineCard: some View {
        WakeCard {
            VStack(spacing: 6) {
                MicroLabel(text: "Need to be awake by")
                Text(TimeFmt.clock(app.deadline.date()))
                    .font(.system(size: 68, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("Wake window begins ~\(TimeFmt.clock(app.plan.windowStart))")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.i2)
                HStack(spacing: 10) {
                    nudge("− 5 min", -5)
                    nudge("+ 5 min", 5)
                }
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func nudge(_ label: String, _ delta: Int) -> some View {
        Button { withAnimation(.snappy) { app.nudgeDeadline(minutes: delta) } } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hair))
        }
        .foregroundStyle(Theme.text)
    }

    private var curveCard: some View {
        WakeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom) {
                    Text("Your sunrise · \(app.plan.windowMinutes)-min")
                        .font(.system(size: 18, weight: .bold))
                    Spacer()
                    MicroLabel(text: "predicted")
                }
                SunriseCurve()
                    .frame(height: 130)
                HStack {
                    Text("gentle · cool"); Spacer(); Text("emergency · hot")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.faint)

                VStack(spacing: 0) {
                    ForEach(Array(zip(app.plan.stages, app.plan.stageTimes)), id: \.0.id) { stage, time in
                        StageRow(stage: stage, time: time)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct StageRow: View {
    let stage: WakeStage
    let time: Date
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(Theme.intensity(stage.intensity))
                .frame(width: 12, height: 12)
                .shadow(color: Theme.intensity(stage.intensity), radius: 6)
            Text(TimeFmt.clock(time))
                .font(.system(size: 15, weight: .bold)).monospacedDigit()
                .frame(width: 58, alignment: .leading)
            Text(stage.name).font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(stage.detail).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
        .overlay(Divider().background(Theme.hair), alignment: .top)
    }
}

/// The hero: a rising curve filled with the night→dawn gradient.
struct SunriseCurve: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: h * 0.93))
                p.addCurve(to: CGPoint(x: w, y: h * 0.05),
                           control1: CGPoint(x: w * 0.45, y: h * 0.85),
                           control2: CGPoint(x: w * 0.7, y: h * 0.2))
            }
            let grad = LinearGradient(colors: [Theme.i0, Theme.i1, Theme.i2, Theme.i3],
                                      startPoint: .leading, endPoint: .trailing)
            ZStack {
                path.strokedPath(.init(lineWidth: 3.5, lineCap: .round))
                    .fill(grad)
                    .background(
                        path.strokedPath(.init(lineWidth: 3.5))
                            .fill(grad).blur(radius: 8).opacity(0.6)
                    )
            }
        }
    }
}
