//
//  AgentPetView.swift
//  NotchPet — AI coding-agent task sync (in-notch pet)
//
//  The reactive "pet" (crab) lives INSIDE the notch (not as a floating desktop window).
//  It animates to the aggregated AI-agent state and is rendered in the closed-notch
//  live activity and the expanded Agents tab.
//

import SwiftUI

struct AgentPetView: View {
    var state: AgentState
    var size: CGFloat = 22
    @State private var animate = false

    private var isBusy: Bool {
        state == .working || state == .thinking || state == .juggling || state == .sweeping
    }

    var body: some View {
        Text("🦀")
            .font(.system(size: size))
            .rotationEffect(.degrees(isBusy ? (animate ? 8 : -8) : 0))
            .scaleEffect(state == .attention ? (animate ? 1.12 : 1.0) : 1.0)
            .shadow(color: state.tint.opacity(state == .idle || state == .sleeping ? 0 : 0.55),
                    radius: 4)
            .overlay(alignment: .topTrailing) {
                if state != .idle && state != .sleeping {
                    Image(systemName: state.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(state.tint)
                        .font(.system(size: max(8, size * 0.42), weight: .semibold))
                        .padding(1)
                        .background(Circle().fill(.black.opacity(0.65)))
                        .offset(x: size * 0.22, y: -size * 0.16)
                }
            }
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animate)
            .animation(.spring(response: 0.3), value: state)
            .onAppear { animate = true }
            .help("AI agent: \(state.label)")
    }
}
