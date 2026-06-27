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
    @Default(.pomodoroLongBreakInterval) private var longBreakInterval

    var body: some View {
        HStack(spacing: 18) {
            ring
                .frame(width: 96, height: 96)

            VStack(alignment: .leading, spacing: 8) {
                header
                controls
                cycleAndStats
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
                    Label(manager.phase.displayName, systemImage: manager.phase.symbol)
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
        }
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

            // Skip to next phase.
            Button(action: manager.skip) {
                controlGlyph("forward.end.fill")
            }
            .buttonStyle(.plain)
            .disabled(manager.phase == .idle)
            .opacity(manager.phase == .idle ? 0.4 : 1)
            .help("Skip phase")

            // Reset to idle.
            Button(action: manager.reset) {
                controlGlyph("stop.fill")
            }
            .buttonStyle(.plain)
            .disabled(manager.phase == .idle)
            .opacity(manager.phase == .idle ? 0.4 : 1)
            .help("Reset")

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
