import SwiftUI

/// First-run popup: ask when you must be up, and how fast you wake. That's enough to
/// build a personal wake plan (no voice recording — Wake judges "I'm awake" on the fly).
struct OnboardingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var time = Calendar.current.date(bySettingHour: 8, minute: 50, second: 0, of: .now) ?? .now
    @State private var speed: WakeSpeed?

    var body: some View {
        ZStack {
            NightBackground()
            VStack(spacing: 0) {
                dots
                Spacer()
                Group {
                    switch step {
                    case 0: welcome
                    case 1: deadlineStep
                    default: speedStep
                    }
                }
                .transition(.opacity)
                Spacer()
                controls
            }
            .padding(28)
        }
        .interactiveDismissDisabled()
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Capsule()
                    .fill(i <= step ? Theme.i2 : Color.white.opacity(0.15))
                    .frame(width: i <= step ? 20 : 7, height: 7)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(spacing: 10) {
            Text("Wake up on a curve")
                .font(.system(size: 30, weight: .heavy)).multilineTextAlignment(.center)
            Text("Tell Wake when you need to be up and how you wake — it builds a personal wake-up plan, then learns every morning.")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 300)
        }
    }

    private var deadlineStep: some View {
        VStack(spacing: 10) {
            Text("When must you be awake?")
                .font(.system(size: 26, weight: .heavy)).multilineTextAlignment(.center)
            Text("Not when the alarm rings — when you need to be out of bed.")
                .font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .padding(.top, 8)
        }
    }

    private var speedStep: some View {
        VStack(spacing: 10) {
            Text("How fast do you wake?")
                .font(.system(size: 26, weight: .heavy)).multilineTextAlignment(.center)
            Text("This sets how early and how gently your first plan begins.")
                .font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            VStack(spacing: 10) {
                option(.immediate, "bolt.fill", "Up immediately", "Out of bed at the first sound")
                option(.gradual, "sunrise.fill", "In a little while", "I need a few minutes to surface")
                option(.manyAlarms, "alarm.waves.left.and.right.fill", "4–5 alarms", "I fight it — keep escalating")
            }
            .padding(.top, 8)
        }
    }

    private func option(_ value: WakeSpeed, _ icon: String, _ title: String, _ sub: String) -> some View {
        Button { withAnimation(.snappy) { speed = value } } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18)).frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 15.5, weight: .bold))
                    Text(sub).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .foregroundStyle(Theme.text)
            .padding(14)
            .background((speed == value ? Theme.i2.opacity(0.14) : Color.white.opacity(0.03)),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(speed == value ? Theme.i2 : Theme.hair, lineWidth: 1))
        }
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        switch step {
        case 0:
            primary("Get started") { withAnimation { step = 1 } }
        case 1:
            primary("Continue") { withAnimation { step = 2 } }
        default:
            primary("Build my plan", enabled: speed != nil) { finish() }
        }
    }

    private func primary(_ label: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 17, weight: .heavy))
                .frame(maxWidth: .infinity).padding(16).foregroundStyle(Color(hex: 0x20090C))
                .background(LinearGradient(colors: [Theme.i2, Theme.i3], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 18))
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    private func finish() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let deadline = WakeDeadline(minutesFromMidnight: (c.hour ?? 8) * 60 + (c.minute ?? 50))
        app.completeOnboarding(deadline: deadline, wakeSpeed: speed ?? .gradual)
        dismiss()
    }
}
