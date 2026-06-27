//
//  PomodoroLiveActivity.swift
//  NotchPet
//
//  Compact strip shown in the CLOSED notch while a Pomodoro session is running:
//  a small phase-tinted ring with the phase symbol + MM:SS. Driven by a
//  TimelineView so it ticks each second without the manager republishing.
//
//  The closed-notch arbiter decides *whether* to show this (see
//  PomodoroManager.shared.isRunning and the show-in-closed-notch setting); this
//  view only renders the content.
//

import SwiftUI
import Defaults

struct PomodoroLiveActivity: View {
    @ObservedObject var manager = PomodoroManager.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let tint = manager.phase.tint
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(manager.progress))
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: manager.phase.symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(tint)
                }
                .frame(width: 18, height: 18)

                Text(manager.remainingString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 4)
            .fixedSize()
        }
    }
}

#if DEBUG
#Preview {
    PomodoroLiveActivity()
        .padding()
        .background(.black)
}
#endif
