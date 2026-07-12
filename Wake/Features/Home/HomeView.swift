import SwiftUI

/// "Home" — your alarms. Each alarm is a card; tap it to expand its wake-up plan.
/// A person can keep several (e.g. a morning and an evening one).
struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var showWake = false
    @State private var expandedID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("You need to be out of bed by your deadline. Wake handles everything before it.")
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)

                    testWakeButton
                    if let est = app.lastSleepEstimate { sleepLine(est) }

                    HStack {
                        Text("Alarms").font(.system(size: 19, weight: .heavy))
                        Spacer()
                    }
                    .padding(.top, 6)

                    ForEach(app.alarms) { alarm in alarmCard(alarm) }
                }
                .padding(20)
            }
            .background(NightBackground())
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        app.addAlarm(hour: 7, minute: 0, label: "Alarm")
                        if let last = app.alarms.last { withAnimation(.snappy) { expandedID = last.id } }
                    } label: { Label("Add alarm", systemImage: "plus") }
                }
            }
            .fullScreenCover(isPresented: $showWake) { WakeSequenceView() }
            .task { await app.refreshSleep() }
        }
    }

    // MARK: - Alarm card

    @ViewBuilder private func alarmCard(_ alarm: Alarm) -> some View {
        let isOpen = expandedID == alarm.id
        WakeCard {
            VStack(alignment: .leading, spacing: 0) {
                // Header row — tap toggles expand.
                HStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(TimeFmt.clock(alarm.deadline.date()))
                            .font(.system(size: 30, weight: .heavy)).monospacedDigit()
                        Text(TimeFmt.ampm(alarm.deadline.date()))
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                    }
                    .opacity(alarm.isEnabled ? 1 : 0.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alarm.label).font(.system(size: 14, weight: .semibold))
                        Text("\(app.plan(for: alarm).windowMinutes)-min wake plan")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Toggle("", isOn: enabledBinding(alarm)).labelsHidden().tint(Theme.i2)
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { expandedID = isOpen ? nil : alarm.id } }

                if isOpen { expanded(alarm) }
            }
        }
    }

    @ViewBuilder private func expanded(_ alarm: Alarm) -> some View {
        let plan = app.plan(for: alarm)
        VStack(alignment: .leading, spacing: 12) {
            Divider().background(Theme.hair).padding(.vertical, 14)

            DatePicker("Be awake by", selection: timeBinding(alarm), displayedComponents: .hourAndMinute)
                .font(.system(size: 14, weight: .semibold))

            Text("Wake window begins ~\(TimeFmt.clock(plan.windowStart))")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.i2)

            SunriseCurve().frame(height: 110)
            HStack { Text("gentle · maroon"); Spacer(); Text("emergency · ember") }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)

            VStack(spacing: 0) {
                ForEach(Array(zip(plan.stages, plan.stageTimes)), id: \.0.id) { stage, time in
                    StageRow(stage: stage, time: time)
                }
            }

            Button(role: .destructive) { withAnimation { app.deleteAlarm(alarm) } } label: {
                Label("Delete alarm", systemImage: "trash").font(.system(size: 14, weight: .semibold))
            }
            .tint(Theme.i2)
            .padding(.top, 4)
        }
    }

    // MARK: - Bindings

    private func enabledBinding(_ alarm: Alarm) -> Binding<Bool> {
        Binding(get: { alarm.isEnabled }, set: { var a = alarm; a.isEnabled = $0; app.update(a) })
    }
    private func timeBinding(_ alarm: Alarm) -> Binding<Date> {
        Binding(get: { alarm.deadline.date() }, set: { newDate in
            let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
            var a = alarm
            a.deadline = WakeDeadline(minutesFromMidnight: (c.hour ?? 7) * 60 + (c.minute ?? 0))
            app.update(a)
        })
    }

    // MARK: - Other bits

    private var testWakeButton: some View {
        Button { showWake = true } label: {
            HStack {
                Image(systemName: "sun.horizon.fill")
                Text("Test the wake-up now").fontWeight(.bold)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold))
            }
            .font(.system(size: 16))
            .foregroundStyle(Color(hex: 0x20090C))
            .padding(16)
            .background(LinearGradient(colors: [Theme.i2, Theme.i3], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private func sleepLine(_ est: SleepEstimate) -> some View {
        let src = est.signals.contains(.healthKit) ? "Health"
                : est.signals.contains(.motion) ? "motion" : "estimate"
        return HStack(spacing: 8) {
            Image(systemName: "bed.double.fill").font(.system(size: 13))
            Text("Fell asleep ~\(TimeFmt.clock(est.sleepStart))").font(.system(size: 13.5, weight: .semibold))
            Text("· \(src)").font(.system(size: 12)).foregroundStyle(Theme.faint)
            Spacer()
        }
        .foregroundStyle(Theme.muted).padding(.horizontal, 6)
    }
}

// MARK: - Shared pieces

private struct StageRow: View {
    let stage: WakeStage
    let time: Date
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Theme.intensity(stage.intensity)).frame(width: 11, height: 11)
                .shadow(color: Theme.intensity(stage.intensity), radius: 5)
            Text(TimeFmt.clock(time)).font(.system(size: 14, weight: .bold)).monospacedDigit()
                .frame(width: 54, alignment: .leading)
            Text(stage.name).font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(stage.detail).font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 10)
        .overlay(Divider().background(Theme.hair), alignment: .top)
    }
}

/// The night→dawn wake curve, filled with the intensity gradient.
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
            path.strokedPath(.init(lineWidth: 3.5, lineCap: .round))
                .fill(grad)
                .background(path.strokedPath(.init(lineWidth: 3.5)).fill(grad).blur(radius: 8).opacity(0.6))
        }
    }
}
