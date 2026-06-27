//
//  HealthReminderSettingsView.swift
//  NotchPet
//
//  Settings UI for the health reminders module (water / posture / sleep).
//  This is the module's only UI — it lives in the app Settings window. Changes are
//  written to Defaults; HealthReminderManager observes those keys and re-arms itself.
//

import SwiftUI
import Defaults

struct HealthReminderSettingsView: View {
    // Water
    @Default(.waterEnabled) private var waterEnabled
    @Default(.waterIntervalMinutes) private var waterInterval

    // Posture
    @Default(.postureEnabled) private var postureEnabled
    @Default(.postureIntervalMinutes) private var postureInterval

    // Sleep
    @Default(.sleepEnabled) private var sleepEnabled
    @Default(.sleepHour) private var sleepHour
    @Default(.sleepMinute) private var sleepMinute

    // Active hours (quiet hours = outside this window)
    @Default(.activeStartHour) private var activeStartHour
    @Default(.activeStartMinute) private var activeStartMinute
    @Default(.activeEndHour) private var activeEndHour
    @Default(.activeEndMinute) private var activeEndMinute

    // Shared
    @Default(.reminderSound) private var reminderSound

    var body: some View {
        Form {
            // MARK: Water
            Section {
                Toggle(isOn: $waterEnabled) {
                    Label("Water reminder", systemImage: HealthReminderKind.water.symbol)
                }
                if waterEnabled {
                    intervalRow(label: "Every", minutes: $waterInterval)
                }
            } header: {
                Text("Hydration")
            } footer: {
                Text("Nudges you to drink water during your active hours.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: Posture
            Section {
                Toggle(isOn: $postureEnabled) {
                    Label("Posture reminder", systemImage: HealthReminderKind.posture.symbol)
                }
                if postureEnabled {
                    intervalRow(label: "Every", minutes: $postureInterval)
                }
            } header: {
                Text("Sedentary")
            } footer: {
                Text("Reminds you to stand up and move after sitting too long.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: Sleep
            Section {
                Toggle(isOn: $sleepEnabled) {
                    Label("Sleep reminder", systemImage: HealthReminderKind.sleep.symbol)
                }
                if sleepEnabled {
                    HStack {
                        Text("Time")
                        Spacer()
                        DatePicker(
                            "",
                            selection: sleepTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                }
            } header: {
                Text("Bedtime")
            } footer: {
                Text("A one-time nudge each day to wind down. Not affected by quiet hours.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: Quiet hours / active window
            Section {
                HStack {
                    Text("Active from")
                    Spacer()
                    DatePicker("", selection: activeStartBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                HStack {
                    Text("until")
                    Spacer()
                    DatePicker("", selection: activeEndBinding, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            } header: {
                Text("Quiet hours")
            } footer: {
                Text("Water & posture reminders only fire inside this window. Outside it (your quiet hours) they stay silent. The window may cross midnight.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: Sound
            Section {
                Toggle("Play sound", isOn: $reminderSound)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Interval row

    @ViewBuilder
    private func intervalRow(label: String, minutes: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            // Clamp to a sane range; repeating notifications need >= 1 min and the
            // notification center enforces a 60s floor anyway.
            Stepper(value: minutes, in: 5...240, step: 5) {
                Text(formatMinutes(minutes.wrappedValue))
                    .monospacedDigit()
            }
            .fixedSize()
        }
    }

    private func formatMinutes(_ m: Int) -> String {
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h) hr" : "\(h) hr \(r) min"
    }

    // MARK: Time bindings (Int hour/minute <-> Date for DatePicker)

    private var sleepTimeBinding: Binding<Date> {
        timeBinding(hour: $sleepHour, minute: $sleepMinute)
    }

    private var activeStartBinding: Binding<Date> {
        timeBinding(hour: $activeStartHour, minute: $activeStartMinute)
    }

    private var activeEndBinding: Binding<Date> {
        timeBinding(hour: $activeEndHour, minute: $activeEndMinute)
    }

    /// Bridges a pair of stored hour/minute Ints to a Date the DatePicker can edit.
    private func timeBinding(hour: Binding<Int>, minute: Binding<Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                let cal = Calendar.current
                var comps = cal.dateComponents([.year, .month, .day], from: Date())
                comps.hour = hour.wrappedValue
                comps.minute = minute.wrappedValue
                return cal.date(from: comps) ?? Date()
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                hour.wrappedValue = comps.hour ?? 0
                minute.wrappedValue = comps.minute ?? 0
            }
        )
    }
}

#if DEBUG
#Preview {
    HealthReminderSettingsView()
        .frame(width: 480, height: 620)
}
#endif
