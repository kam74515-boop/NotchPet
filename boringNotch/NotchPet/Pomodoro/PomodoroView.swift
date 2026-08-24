//
//  PomodoroView.swift
//  NotchPet
//
//  The expanded-notch Pomodoro tab: a circular countdown ring with big MM:SS,
//  phase label, transport controls, cycle dots and today's completed count.
//  Sized for the ~600pt wide, ~145pt tall expanded content area on black.
//

import SwiftUI
import Defaults

struct PomodoroView: View {
    @ObservedObject var manager = PomodoroManager.shared
    @Default(.pomodoroWorkMinutes) private var workMinutes
    @Default(.pomodoroShortBreakMinutes) private var shortBreakMinutes
    @Default(.pomodoroLongBreakMinutes) private var longBreakMinutes
    @Default(.pomodoroLongBreakInterval) private var longBreakInterval
    @State private var isEditingDurations = false

    var body: some View {
        HStack(spacing: 18) {
            ring
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                header
                if isEditingDurations {
                    durationEditor
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    controls
                    cycleAndStats
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Ring

    private var ring: some View {
        // TimelineView keeps the ring & digits ticking smoothly even though the
        // manager only republishes once per second.
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let tint = manager.phase.tint
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: CGFloat(manager.progress))
                    .stroke(
                        tint,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.5), radius: 4)
                    .animation(.linear(duration: 0.25), value: manager.progress)

                VStack(spacing: 1) {
                    Text(manager.remainingString)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Label(LocalizedStringKey(manager.phase.displayName), systemImage: manager.phase.symbol)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "timer")
                .foregroundStyle(.secondary)
            Text("Pomodoro")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            if manager.isPaused {
                Text("Paused")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isEditingDurations.toggle()
                }
            } label: {
                Label(
                    LocalizedStringKey(isEditingDurations ? "Done" : "Set time"),
                    systemImage: isEditingDurations ? "checkmark" : "slider.horizontal.3"
                )
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(Color.white.opacity(isEditingDurations ? 0.16 : 0.08), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help(isEditingDurations ? "Finish setting durations" : "Set Pomodoro durations in the notch")
            .accessibilityLabel(isEditingDurations ? "Done setting durations" : "Set Pomodoro durations")
        }
    }

    // MARK: Duration editor

    private var durationEditor: some View {
        VStack(spacing: 2) {
            durationRow("Focus", icon: "brain.head.profile", minutes: $workMinutes,
                        range: 1...120, presets: [15, 25, 45, 60])
            durationRow("Short break", icon: "cup.and.saucer.fill", minutes: $shortBreakMinutes,
                        range: 1...60, presets: [5, 10, 15, 20])
            durationRow("Long break", icon: "figure.walk", minutes: $longBreakMinutes,
                        range: 1...90, presets: [10, 15, 20, 30])
            if manager.phase != .idle {
                Text("Changes apply to the next phase")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func durationRow(
        _ title: LocalizedStringKey,
        icon: String,
        minutes: Binding<Int>,
        range: ClosedRange<Int>,
        presets: [Int]
    ) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                minutes.wrappedValue = max(range.lowerBound, minutes.wrappedValue - 1)
            } label: {
                durationGlyph("minus")
            }
            .buttonStyle(.plain)
            .disabled(minutes.wrappedValue <= range.lowerBound)
            .accessibilityLabel("Decrease duration")

            Menu {
                ForEach(presets, id: \.self) { preset in
                    Button("\(preset) min") { minutes.wrappedValue = preset }
                }
            } label: {
                Text("\(minutes.wrappedValue) min")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 52, height: 22)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Choose a preset")

            Button {
                minutes.wrappedValue = min(range.upperBound, minutes.wrappedValue + 1)
            } label: {
                durationGlyph("plus")
            }
            .buttonStyle(.plain)
            .disabled(minutes.wrappedValue >= range.upperBound)
            .accessibilityLabel("Increase duration")
        }
        .frame(height: 24)
    }

    private func durationGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 9, weight: .bold))
            .frame(width: 22, height: 22)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(.white)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            // Primary: start / pause / resume.
            Button(action: manager.toggle) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 28)
                    .background(manager.phase.tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help(manager.isRunning ? "Pause" : (manager.phase == .idle ? "Start" : "Resume"))
            .accessibilityLabel(manager.isRunning ? "Pause Pomodoro" : (manager.phase == .idle ? "Start Pomodoro" : "Resume Pomodoro"))

            // Skip to next phase.
            Button(action: manager.skip) {
                controlGlyph("forward.end.fill")
            }
            .buttonStyle(.plain)
            .disabled(manager.phase == .idle)
            .opacity(manager.phase == .idle ? 0.4 : 1)
            .help("Skip phase")
            .accessibilityLabel("Skip Pomodoro phase")

            // Reset to idle.
            Button(action: manager.reset) {
                controlGlyph("stop.fill")
            }
            .buttonStyle(.plain)
            .disabled(manager.phase == .idle)
            .opacity(manager.phase == .idle ? 0.4 : 1)
            .help("Reset")
            .accessibilityLabel("Reset Pomodoro")

            Spacer()
        }
    }

    private var primaryIcon: String {
        if manager.phase == .idle { return "play.fill" }
        return manager.isRunning ? "pause.fill" : "play.fill"
    }

    private func controlGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12, weight: .semibold))
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            .foregroundStyle(.white)
    }

    // MARK: Cycle dots + today's count

    /// How many dots in the current cycle should appear "filled".
    /// When the cycle is exactly complete (about to take a long break) all are lit.
    private var filledDots: Int {
        let interval = max(1, longBreakInterval)
        let pos = manager.cyclePosition % interval
        return (pos == 0 && manager.cyclePosition > 0) ? interval : pos
    }

    private var cycleAndStats: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(0..<max(1, longBreakInterval), id: \.self) { i in
                    Circle()
                        .fill(i < filledDots ? PomodoroPhase.work.tint : Color.white.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
            }
            .help("Focus sessions until a long break")

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(PomodoroPhase.shortBreak.tint)
                Text("\(manager.stats.completedToday) today")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11, weight: .medium))
        }
    }
}

#if DEBUG
#Preview {
    PomodoroView()
        .frame(width: 600, height: 145)
        .background(.black)
}
#endif
