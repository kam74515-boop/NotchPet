//
//  AgentSyncViews.swift
//  NotchPet — AI coding-agent task sync (UI)
//

import SwiftUI
import Defaults

// MARK: - Closed-notch live activity

/// Compact indicator shown in the closed notch while an agent is active (or just finished).
struct AgentLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var store = AgentSessionStore.shared
    @ObservedObject var coord = AgentSyncCoordinator.shared

    private var side: CGFloat { max(0, vm.effectiveClosedNotchHeight - 12) }

    var body: some View {
        // A just-completed peek takes precedence, then the live display state.
        let peek = coord.completionPeek
        let state = peek?.state ?? store.displayState
        let title = peek?.title ?? store.displaySession?.title ?? "Agent"

        HStack(spacing: 0) {
            HStack {
                if Defaults[.agentPetEnabled] {
                    AgentPetView(state: state, size: max(12, side - 2))
                        .frame(width: side, height: side)
                } else {
                    Image(systemName: state.symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(state.tint)
                        .font(.system(size: max(10, side - 4)))
                        .frame(width: side, height: side)
                }
            }

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width + 8)

            HStack(spacing: 3) {
                if store.workingTier > 1 {
                    Text("\(store.workingTier)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                if let pct = store.displaySession?.contextPercent {
                    Text("\(Int(pct))%")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: side, height: side, alignment: .trailing)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .help(title)
    }
}

// MARK: - Open-notch "Agents" tab

struct AgentsTabView: View {
    @ObservedObject var store = AgentSessionStore.shared
    @ObservedObject var coord = AgentSyncCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                AgentPetView(state: store.displayState, size: 18)
                    .frame(width: 20, height: 20)
                Text("AI Agents")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if coord.running {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("port \(Int(coord.activePort ?? 0))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            if !coord.running {
                emptyState(icon: "bolt.slash",
                           text: "AI sync is off.",
                           action: ("Enable", { coord.setEnabled(true) }))
            } else if store.sessions.isEmpty {
                emptyState(icon: "moon.zzz",
                           text: "No active agents. Start a task in Claude Code.",
                           action: nil)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(store.orderedSessions) { session in
                            AgentSessionRow(session: session)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func emptyState(icon: String, text: String, action: (String, () -> Void)?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1).buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AgentSessionRow: View {
    let session: AgentSession
    @ObservedObject var store = AgentSessionStore.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.state.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(session.state.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(session.state.label).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if let pct = session.contextPercent {
                Text("\(Int(pct))%").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if session.requiresAck {
                Button {
                    store.ack(session.id)
                } label: {
                    Image(systemName: "checkmark").font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Mark as seen")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Settings pane

struct AgentSyncSettingsView: View {
    @ObservedObject var coord = AgentSyncCoordinator.shared
    @Default(.agentSyncEnabled) var enabled
    @Default(.agentCompletionNotification) var completionNote
    @Default(.agentCompletionSound) var completionSound
    @Default(.agentShowInClosedNotch) var showInNotch
    @Default(.agentPermissionsEnabled) var permissions
    @Default(.agentPetEnabled) var petEnabled

    var body: some View {
        Form {
            Section("AI Agent Sync") {
                Toggle("Enable agent sync", isOn: Binding(
                    get: { enabled },
                    set: { coord.setEnabled($0) }))
                Text("The notch and desktop pet react to Claude Code (and compatible CLIs) in real time — and tell you when a long task finishes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Claude Code hooks") {
                HStack {
                    Circle().fill(coord.hooksInstalled ? .green : .secondary).frame(width: 8, height: 8)
                    Text(coord.hooksInstalled ? "Hooks installed" : "Hooks not installed")
                    Spacer()
                    Button("Install / Repair") { coord.reinstallHooks() }
                    Button("Remove") { coord.removeHooks() }
                }
                if !coord.lastInstallMessage.isEmpty {
                    Text(coord.lastInstallMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text("Hooks are merged into ~/.claude/settings.json (your own hooks are preserved).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("System notification on completion", isOn: $completionNote)
                Toggle("Play sound", isOn: $completionSound)
                Toggle("Show status in closed notch", isOn: $showInNotch)
            }

            Section("Pet") {
                Toggle("Show reactive pet in the notch", isOn: Binding(
                    get: { petEnabled },
                    set: { coord.setPetEnabled($0) }))
                Text("A little crab inside the notch reacts to your AI agents' state. Turn off to show a minimal status icon instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Permissions (advanced)") {
                Toggle("Answer permission requests in NotchPet", isOn: $permissions)
                Text("When on, tool-permission prompts appear as a bubble. When off, Claude Code keeps using its own terminal prompt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { coord.refreshHookStatus() }
    }
}
