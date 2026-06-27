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
                // Clean status glyph (✓ done / 🔔 needs-you / ⚠ error) — no persistent pet.
                Image(systemName: state.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(state.tint)
                    .font(.system(size: max(10, side - 4)))
                    .frame(width: side, height: side)
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
                if Defaults[.agentPetEnabled] {
                    AgentPetView(state: store.displayState, size: 18)
                        .frame(width: 20, height: 20)
                }
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

    private var dotColor: Color {
        switch session.state {
        case .working, .thinking, .juggling, .sweeping, .carrying: return .blue
        case .attention: return .green
        case .error: return .red
        case .notification: return .orange
        case .idle, .sleeping: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status dot (blue = active, green = done, red = error, gray = idle).
            Circle().fill(dotColor).frame(width: 8, height: 8)

            // Which software this task belongs to.
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(AgentKind.tint(session.agentId).opacity(0.22))
                Image(systemName: AgentKind.symbol(session.agentId))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AgentKind.tint(session.agentId))
            }
            .frame(width: 22, height: 22)
            .help(AgentKind.name(session.agentId))

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                Text("\(AgentKind.name(session.agentId)) · \(session.state.label)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            badge
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture { if session.requiresAck { store.ack(session.id) } }
    }

    @ViewBuilder
    private var badge: some View {
        if session.requiresAck {
            pill(text: "Done", color: .green)
        } else if session.state == .error {
            pill(text: "Error", color: .red)
        } else if let pct = session.contextPercent {
            Text("\(Int(pct))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func pill(text: LocalizedStringKey, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
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
                Toggle("Show the crab on the Agents page", isOn: Binding(
                    get: { petEnabled },
                    set: { coord.setPetEnabled($0) }))
                Text("The notch stays clean — it only pops a brief status when a task finishes, errors, or needs your input. The crab lives on the Agents tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Coding tools") {
                Text("NotchPet reuses clawd-on-desk's ready-made installers to capture tasks from many CLIs/IDEs. Toggle which to hook (Claude Code is always on above).")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(MultiAgentInstaller.agents) { a in
                    Toggle(AgentKind.name(a.id), isOn: Binding(
                        get: { Defaults[.enabledCodingAgents][a.id] ?? a.defaultEnabled },
                        set: { on in
                            var m = Defaults[.enabledCodingAgents]
                            m[a.id] = on
                            Defaults[.enabledCodingAgents] = m
                            Task {
                                if on { _ = await MultiAgentInstaller.install(a) }
                                else { _ = await MultiAgentInstaller.uninstall(a) }
                            }
                        }))
                }
                Button("Reinstall all tool hooks") { coord.reinstallAllAgents() }
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
