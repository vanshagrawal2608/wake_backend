import SwiftUI

/// "Wake" — the live morning experience. Halo shows the current stage; voice
/// confirmation is the only thing that stops the alarm (and only if you sound awake).
struct WakeSequenceView: View {
    @Environment(AppState.self) private var app
    @State private var stageIndex = 2
    @State private var voice: WakeSession.VoiceFeedback = .idle
    @State private var listening = false
    @State private var reading: Wakefulness?
    @State private var decision: WakeDecision?

    private var stage: WakeStage { app.plan.stages[min(stageIndex, app.plan.stages.count - 1)] }
    private var color: Color { Theme.intensity(stage.intensity) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    halo
                    ladder
                    actions
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(NightBackground())
            .navigationTitle("Waking you")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var halo: some View {
        ZStack {
            Circle().stroke(Theme.hair, lineWidth: 1.5).frame(width: 230, height: 230)
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.6), .clear],
                                     center: .center, startRadius: 10, endRadius: 120))
                .frame(width: 210, height: 210)
                .blur(radius: 6)
                .modifier(Breathe())
            VStack(spacing: 3) {
                MicroLabel(text: "Stage \(stage.id + 1) of \(app.plan.stages.count)")
                Text(stage.name).font(.system(size: 26, weight: .heavy))
                Text(stage.detail).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 240)
    }

    private var ladder: some View {
        HStack(spacing: 6) {
            ForEach(app.plan.stages) { s in
                Capsule()
                    .fill(s.id <= stageIndex ? color : Color.white.opacity(0.12))
                    .frame(width: 26, height: 6)
                    .shadow(color: s.id <= stageIndex ? color : .clear, radius: 5)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: talk) {
                HStack(spacing: 12) {
                    Image(systemName: listening ? "waveform" : "mic.fill")
                    Text(micLabel)
                }
                .font(.system(size: 17, weight: .heavy))
                .frame(maxWidth: .infinity)
                .padding(17)
                .foregroundStyle(listening ? .white : Color(hex: 0x0B0B16))
                .background(micBackground, in: RoundedRectangle(cornerRadius: 20))
            }
            Text(voiceFeed)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(voice == .awake ? Theme.good : (voice == .groggy ? Theme.i2 : Theme.muted))
                .multilineTextAlignment(.center)
                .frame(minHeight: 40)

            Button { stillWaking() } label: {
                Text("I’m still waking up")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity).padding(15)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hair))
            }
            .foregroundStyle(Theme.text)
        }
    }

    private var micLabel: String {
        switch voice {
        case .listening: return "Listening…"
        case .awake: return "You’re up"
        default: return "Hold to say “I’m awake”"
        }
    }
    private var micBackground: AnyShapeStyle {
        listening ? AnyShapeStyle(LinearGradient(colors: [Theme.i0, Theme.i1], startPoint: .top, endPoint: .bottom))
                  : AnyShapeStyle(LinearGradient(colors: [.white, Color(hex: 0xDFE2F2)], startPoint: .top, endPoint: .bottom))
    }
    private var voiceFeed: String {
        if let d = decision, voice != .idle {
            switch voice {
            case .awake:
                let via = d.source == .gemini ? "confirmed by Gemini" : "on-device"
                return "Clear “I’m awake” (\(via)). Good morning. ☀️"
            case .groggy where !d.heardPhrase:
                return "Didn’t catch it — say exactly “I’m awake”."
            case .groggy:
                return d.reasoning
            default:
                return "Listening…"
            }
        }
        switch voice {
        case .awake:  return "Confirmed awake — alarm stopped. ☀️"
        case .groggy: return "Say “I’m awake” clearly to stop the alarm."
        default:      return "Say “I’m awake” clearly — checked on-device, and by Gemini if unsure."
        }
    }

    // MARK: - Interaction — capture on-device, judge (Gemini only when unsure).

    private func talk() {
        guard !listening else { return }
        listening = true; voice = .listening; reading = nil; decision = nil

        Task {
            let authorized = await app.voice.requestAuthorization()
            guard authorized else { await simulate(); return }

            app.voice.listen { r in
                Task { @MainActor in
                    self.reading = r
                    if r.isFinal { await self.decide(r) }
                }
            }
            try? await Task.sleep(for: .seconds(5))         // give the user time, then finalize
            app.voice.stop()
        }
    }

    @MainActor private func decide(_ r: Wakefulness) async {
        guard listening else { return }
        let d = await app.judgeAwake(clarity: r.clarity,
                                     heardPhrase: r.heardExpectedPhrase,
                                     morningAudio: app.voice.lastClipData)
        guard listening else { return }
        listening = false; decision = d
        if d.isAwake {
            voice = .awake; app.confirmAwake()
            withAnimation(.snappy) { stageIndex = app.plan.stages.count - 1 }
        } else {
            voice = .groggy
        }
    }

    /// Fallback for the simulator / previews where there's no microphone.
    @MainActor private func simulate() async {
        try? await Task.sleep(for: .seconds(1.2))
        let clear = Bool.random() || Bool.random()          // ~75% clear
        let d = WakeDecision(isAwake: clear, clarity: clear ? 0.86 : 0.5,
                             confidence: clear ? 0.86 : 0.5, heardPhrase: true,
                             reasoning: clear ? "Clear “I’m awake”." : "Sounds slurred — you’re still half-asleep.",
                             source: .local)
        reading = Wakefulness(heardExpectedPhrase: true, clarity: d.clarity,
                              transcript: clear ? "I'm awake" : "i'm… awake", isFinal: true)
        decision = d
        listening = false
        if clear { voice = .awake; app.confirmAwake(); withAnimation(.snappy) { stageIndex = app.plan.stages.count - 1 } }
        else { voice = .groggy }
    }

    private func stillWaking() {
        voice = .idle; reading = nil
        withAnimation { stageIndex = max(0, stageIndex - 1) }   // soften, no fixed snooze
        app.enterStage(stageIndex)
    }
}

/// Apple-Health-style breathing glow, respecting Reduce Motion.
private struct Breathe: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.06 : 0.9)
            .opacity(on ? 0.7 : 0.4)
            .animation(reduce ? nil : .easeInOut(duration: 3.6).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
