//
//  PomodoroSettingsView.swift
//  NotchPet
//
//  Settings pane for the Pomodoro module: phase durations, long-break interval,
//  auto-start, sound and closed-notch visibility. All controls bind directly to
//  Defaults so changes take effect immediately.
//

import SwiftUI
import Defaults

struct PomodoroSettingsView: View {
    @Default(.pomodoroWorkMinutes) private var workMinutes
    @Default(.pomodoroShortBreakMinutes) private var shortMinutes
    @Default(.pomodoroLongBreakMinutes) private var longMinutes
    @Default(.pomodoroLongBreakInterval) private var longInterval
    @Default(.pomodoroAutoStart) private var autoStart
    @Default(.pomodoroPlaySound) private var playSound
    @Default(.pomodoroShowInClosedNotch) private var showInClosedNotch

    var body: some View {
        Form {
            Section("Durations") {
                Stepper(value: $workMinutes, in: 1...120) {
                    LabeledContent("Focus", value: "\(workMinutes) min")
                }
                Stepper(value: $shortMinutes, in: 1...60) {
                    LabeledContent("Short break", value: "\(shortMinutes) min")
                }
                Stepper(value: $longMinutes, in: 1...90) {
                    LabeledContent("Long break", value: "\(longMinutes) min")
                }
                Stepper(value: $longInterval, in: 2...12) {
                    LabeledContent("Long break after", value: "\(longInterval) sessions")
                }
            }

            Section("Behavior") {
                Toggle("Auto-start next phase", isOn: $autoStart)
                Toggle("Play sound on completion", isOn: $playSound)
                Toggle("Show in closed notch while running", isOn: $showInClosedNotch)
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview {
    PomodoroSettingsView()
        .frame(width: 420, height: 360)
}
#endif
