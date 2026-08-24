//
//  PomodoroLiveActivity.swift
//  NotchPet
//
//  Compact strip shown in the CLOSED notch while a Pomodoro session is running:
//  a phase-tinted ring to the left of the physical notch and MM:SS to its right. Driven by a
//  TimelineView so it ticks each second without the manager republishing.
//
//  The closed-notch arbiter decides *whether* to show this (see
//  PomodoroManager.shared.isRunning and the show-in-closed-notch setting); this
//  view only renders the content.
//

import SwiftUI
import Defaults

struct PomodoroLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var manager = PomodoroManager.shared
    let sideLaneWidth: CGFloat

    init(sideLaneWidth: CGFloat = 50) {
        self.sideLaneWidth = sideLaneWidth
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let tint = manager.phase.tint
            HStack(spacing: 0) {
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
                .frame(width: sideLaneWidth, alignment: .trailing)

                // Keep content out from behind the real camera cutout. closedNotchSize is
                // derived from this screen's auxiliary safe areas, not a fixed assumed width.
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width + 8)

                Text(manager.remainingString)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: sideLaneWidth, alignment: .leading)
            }
            .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        }
    }
}

#if DEBUG
#Preview {
    PomodoroLiveActivity()
        .padding()
        .background(.black)
        .environmentObject(BoringViewModel())
}
#endif
