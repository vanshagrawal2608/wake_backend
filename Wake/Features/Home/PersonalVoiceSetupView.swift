import SwiftUI

/// Set an alarm to wake you in **your own voice** (Apple Personal Voice, free/on-device).
/// You create the voice once in Settings; here you type the line and we render it.
struct PersonalVoiceSetupView: View {
    let alarm: Alarm
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    enum Phase: Equatable { case checking, needsSetup, ready, rendering, failed }
    @State private var phase: Phase = .checking
    @State private var message = "Wake up! It’s time to get up. Come on — you need to wake up now."

    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                content.padding(24)
            }
            .navigationTitle("Wake me in my voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .task { await check() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .checking:
            ProgressView().tint(Theme.i2)
        case .needsSetup:
            setupNeeded
        case .ready, .rendering, .failed:
            editor
        }
    }

    private var setupNeeded: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.mic").font(.system(size: 40)).foregroundStyle(Theme.i2)
            Text("Create your Personal Voice first")
                .font(.system(size: 20, weight: .heavy)).multilineTextAlignment(.center)
            Text("On iOS: Settings → Accessibility → Personal Voice → Create a Voice. It records ~15 minutes and stays private on your device. Then come back here.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(.system(size: 16, weight: .heavy)).foregroundStyle(Color(hex: 0x20090C))
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(LinearGradient(colors: [Theme.i2, Theme.i3], startPoint: .leading, endPoint: .trailing),
                        in: Capsule())
            Button("Check again") { Task { await check() } }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            MicroLabel(text: "What should your voice say?")
            TextEditor(text: $message)
                .scrollContentBackground(.hidden)
                .frame(height: 110)
                .padding(10)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hair))
                .foregroundStyle(Theme.text)

            if phase == .failed {
                Text("Couldn’t render — make sure your Personal Voice is ready, then try again.")
                    .font(.system(size: 13)).foregroundStyle(Theme.i2)
            }

            Spacer()
            Button(action: generate) {
                HStack {
                    if phase == .rendering { ProgressView().tint(Color(hex: 0x20090C)) }
                    Text(phase == .rendering ? "Generating…" : "Use my voice for this alarm")
                }
                .font(.system(size: 17, weight: .heavy))
                .frame(maxWidth: .infinity).padding(16).foregroundStyle(Color(hex: 0x20090C))
                .background(LinearGradient(colors: [Theme.i2, Theme.i3], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 18))
            }
            .disabled(phase == .rendering || message.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func check() async {
        phase = .checking
        let ok = await app.personalVoice.requestAuthorization()
        phase = (ok && app.personalVoice.personalVoice != nil) ? .ready : .needsSetup
    }

    private func generate() {
        phase = .rendering
        Task {
            let ok = await app.setPersonalVoiceAudio(text: message, for: alarm)
            phase = ok ? .ready : .failed
            if ok { dismiss() }
        }
    }
}
