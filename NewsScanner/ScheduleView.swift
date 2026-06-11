import SwiftUI

/// Schedule settings — mirrors the extension's dropdown + conditional inputs.
struct ScheduleView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Scan frequency") {
                Picker("Frequency", selection: $settings.preset) {
                    ForEach(SchedulePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            if settings.preset == .daily {
                Section("Time") {
                    DatePicker(
                        "Scan daily at",
                        selection: dailyTimeBinding,
                        displayedComponents: .hourAndMinute)
                }
            }

            if settings.preset == .custom {
                Section("Interval") {
                    Stepper(
                        "Every \(settings.customMinutes) min",
                        value: $settings.customMinutes,
                        in: 1...1440)
                }
            }

            Section {
                Text("Exact timing applies while the app is open. In the background, "
                     + "iOS schedules scans opportunistically — they may be delayed by "
                     + "hours and aren't guaranteed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dailyTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: settings.dailyHour,
                    minute: settings.dailyMinute,
                    second: 0,
                    of: .now) ?? .now
            },
            set: { newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                settings.dailyHour = comps.hour ?? 9
                settings.dailyMinute = comps.minute ?? 0
            }
        )
    }
}
