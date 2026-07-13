import SwiftUI

/// Popup shown when tapping "+" — pick the wake time and a label before the alarm
/// is created (nothing is added until you tap "Add alarm").
struct AddAlarmView: View {
    var onAdd: (WakeDeadline, String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var time = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: .now) ?? .now
    @State private var label = ""

    var body: some View {
        NavigationStack {
            ZStack {
                NightBackground()
                VStack(spacing: 22) {
                    MicroLabel(text: "Be awake by")
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden().colorScheme(.dark)

                    TextField("Label (e.g. Morning, Gym)", text: $label)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16, weight: .semibold))
                        .padding(14)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hair))

                    Spacer()
                    Button(action: add) {
                        Text("Add alarm").font(.system(size: 17, weight: .heavy))
                            .frame(maxWidth: .infinity).padding(16).foregroundStyle(Color(hex: 0x20090C))
                            .background(LinearGradient(colors: [Theme.i2, Theme.i3], startPoint: .leading, endPoint: .trailing),
                                        in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(24)
            }
            .navigationTitle("New alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func add() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        onAdd(WakeDeadline(minutesFromMidnight: (c.hour ?? 7) * 60 + (c.minute ?? 0)), label)
        dismiss()
    }
}
