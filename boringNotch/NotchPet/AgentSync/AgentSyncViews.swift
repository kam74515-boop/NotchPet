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
                if let remain = store.displaySession?.contextRemainingPercent {
                    Text("\(remain)%")   // context remaining
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
                // No crab mascot ("Clawd" is clawd-on-desk's character) and no "智能体" label —
                // this is NotchPet's own coding-task monitor.
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("AI Coding")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    coord.setAutoPilotEnabled(!coord.autoPilotEnabled)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: coord.autoPilotEnabled ? "bolt.fill" : "bolt")
                        Text("Auto-pilot")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(coord.autoPilotEnabled ? Color.red : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(coord.autoPilotEnabled ? Color.red.opacity(0.18) : Color.white.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help(coord.autoPilotEnabled ? "Turn off auto-pilot" : "Turn on auto-pilot")
                if coord.running {
                    Circle().fill(.green).frame(width: 6, height: 6)
                    Text("port \(Int(coord.activePort ?? 0))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            // An AskUserQuestion answered IN the notch takes over the whole panel (so its options
            // fit without scrolling); otherwise show the permission card + the session list.
            if let clar = coord.pendingClarification {
                ClarificationCard(clarification: clar)
            } else if !coord.running {
                emptyState(icon: "bolt.slash",
                           text: "AI sync is off.",
                           action: ("Enable", { coord.setEnabled(true) }))
            } else {
                if let perm = coord.pendingPermission { permissionCard(perm) }
                if store.sessions.isEmpty {
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
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func permissionCard(_ perm: PendingPermission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                Text("Permission request").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(perm.payload.toolName).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Text(permissionDetail(perm.payload))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button("Deny") { coord.resolvePermission(.deny) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Allow") { coord.resolvePermission(.allow) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.4), lineWidth: 1))
    }

    private func permissionDetail(_ p: PermissionRequestPayload) -> String {
        if let input = p.rawJSON["tool_input"] as? [String: Any] {
            if let cmd = input["command"] as? String { return cmd }
            if let path = input["path"] as? String { return path }
            if let file = input["file_path"] as? String { return file }
        }
        return p.toolName
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

/// Reports the clarification card's natural height up to the notch sizing.
private struct ClarCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// An AskUserQuestion answered right in the notch — pick option(s), submit back to Claude Code,
/// or defer to the terminal. (Submitting uses the PermissionRequest hook's updatedInput.answers.)
struct ClarificationCard: View {
    let clarification: PendingClarification
    @ObservedObject var coord = AgentSyncCoordinator.shared
    @ObservedObject var store = AgentSessionStore.shared
    @State private var selections: [UUID: Set<UUID>] = [:]   // questionID → selected optionIDs
    @State private var customText: [UUID: String] = [:]      // questionID → typed custom answer
    @State private var step = 0                              // current question (one at a time)

    /// Which conversation is asking (so the user knows what this is about).
    private var convoTitle: String { store.sessions[clarification.sessionId]?.title ?? "" }

    private func answered(_ q: ClarificationQuestion) -> Bool {
        !(selections[q.id]?.isEmpty ?? true)
            || !(customText[q.id]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    var body: some View {
        let questions = clarification.questions
        let idx = min(step, max(0, questions.count - 1))
        let q = questions[idx]
        let isLast = idx >= questions.count - 1
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
                    Text("Needs your answer").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    if questions.count > 1 {
                        Text("\(idx + 1)/\(questions.count)")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                    Button("Go to terminal") { coord.clarificationToTerminal() }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                }
                if !convoTitle.isEmpty {
                    Text(convoTitle)
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            // Hug the content: the card reports its natural height (below) and the notch sizes to
            // match, so the bottom sits right under the nav with uniform margins and no scroll.
            questionBody(q, idx: idx, isLast: isLast)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.4), lineWidth: 1))
        // Report the card's natural height so the notch can size to fit it exactly (uniform margins).
        .background(GeometryReader { geo in
            Color.clear.preference(key: ClarCardHeightKey.self, value: geo.size.height)
        })
        .onPreferenceChange(ClarCardHeightKey.self) { h in
            // Ignore 0/teardown reports (they'd briefly shrink the notch and cause a visible jump).
            guard h > 1 else { return }
            if abs(coord.clarificationCardHeight - h) > 0.5 { coord.clarificationCardHeight = h }
        }
    }

    @ViewBuilder
    private func questionBody(_ q: ClarificationQuestion, idx: Int, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !q.question.isEmpty {
                Text(q.question)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(q.options) { opt in optionButton(q, opt) }
                customInputRow(q)
            }
            HStack(spacing: 8) {
                if idx > 0 {
                    Button("Previous") { step -= 1 }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Spacer()
                Button(isLast ? "Submit" : "Next") { advance(from: q, isLast: isLast) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(!answered(q))
            }
            .padding(.top, 2)
        }
    }

    private func advance(from q: ClarificationQuestion, isLast: Bool) {
        guard answered(q) else { return }
        if isLast { submit() } else { step += 1 }
    }

    private func optionButton(_ q: ClarificationQuestion, _ opt: ClarificationOption) -> some View {
        let selected = selections[q.id]?.contains(opt.id) ?? false
        return Button { toggle(q, opt) } label: {
            HStack(spacing: 6) {
                Image(systemName: selected
                      ? (q.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (q.multiSelect ? "square" : "circle"))
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? .orange : .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(opt.label).font(.system(size: 11)).foregroundStyle(.white)
                    if !opt.description.isEmpty {
                        Text(opt.description).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5)).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(selected ? 0.16 : 0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The "Other" row — same look as an option (icon + selected highlight) but with a text field.
    private func customInputRow(_ q: ClarificationQuestion) -> some View {
        let selected = !(customText[q.id]?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        return HStack(spacing: 6) {
            Image(systemName: selected
                  ? (q.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                  : (q.multiSelect ? "square" : "circle"))
                .font(.system(size: 11))
                .foregroundStyle(selected ? .orange : .white.opacity(0.4))
            TextField("Or type your own…", text: Binding(
                get: { customText[q.id] ?? "" },
                set: { v in
                    customText[q.id] = v
                    // Single-select: typing replaces the picked option. Multi-select: the typed
                    // answer is ADDITIONAL to whatever boxes are checked, so don't clear them.
                    if !q.multiSelect, !v.trimmingCharacters(in: .whitespaces).isEmpty { selections[q.id] = [] }
                }))
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.white)
                .onSubmit { advance(from: q, isLast: clarification.questions.last?.id == q.id) }   // Enter = next/submit
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(selected ? 0.16 : 0.06)))
    }

    private func toggle(_ q: ClarificationQuestion, _ opt: ClarificationOption) {
        var set = selections[q.id] ?? []
        if q.multiSelect {
            // Multi-select: checking a box leaves any typed custom answer intact (they coexist).
            if set.contains(opt.id) { set.remove(opt.id) } else { set.insert(opt.id) }
            selections[q.id] = set
        } else {
            customText[q.id] = ""   // single-select: picking an option clears the typed answer
            selections[q.id] = [opt.id]
            // Single-select: picking auto-advances to the next question (or submits if last).
            advance(from: q, isLast: clarification.questions.last?.id == q.id)
        }
    }

    private func submit() {
        var answers: [String: String] = [:]
        for q in clarification.questions {
            // Combine checked option labels with any typed custom answer (multi-select can have
            // both; single-select clears one when the other is set, so this stays a single value).
            var parts = q.options.filter { selections[q.id]?.contains($0.id) ?? false }.map(\.label)
            let custom = customText[q.id]?.trimmingCharacters(in: .whitespaces) ?? ""
            if !custom.isEmpty { parts.append(custom) }
            if !parts.isEmpty { answers[q.question] = parts.joined(separator: ", ") }
        }
        coord.resolveClarification(answers)
    }
}

/// A status dot that "breathes" (pulsing glow) while the agent is generating.
struct StatusDot: View {
    let state: AgentState
    var size: CGFloat = 9
    @State private var pulse = false

    private var color: Color {
        switch state {
        case .working, .thinking, .juggling, .sweeping, .carrying: return .blue
        case .attention: return .green
        case .error: return .red
        case .notification: return .orange
        case .idle, .sleeping: return Color.secondary
        }
    }

    /// "AI 生成中" — thinking/working/subagents/compacting.
    private var isGenerating: Bool {
        switch state {
        case .thinking, .working, .juggling, .sweeping: return true
        default: return false
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(isGenerating && pulse ? 1.35 : 1.0)
            .opacity(isGenerating && pulse ? 0.55 : 1.0)
            .shadow(color: isGenerating ? color.opacity(0.9) : .clear, radius: pulse ? 5 : 0)
            .animation(isGenerating
                       ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                       : .easeOut(duration: 0.2),
                       value: pulse)
            .onAppear { pulse = isGenerating }
            .onChange(of: isGenerating) { _, g in pulse = g }
    }
}

struct AgentSessionRow: View {
    let session: AgentSession
    @ObservedObject var store = AgentSessionStore.shared

    var body: some View {
        HStack(spacing: 8) {
            // Breathing status dot (blue=generating, green=done, red=error, gray=idle).
            StatusDot(state: session.state)

            // Which software this task belongs to — real tool logo (from clawd's icons),
            // falling back to a tinted SF Symbol.
            Group {
                if let logo = AgentKind.image(session.agentId) {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(AgentKind.tint(session.agentId).opacity(0.22))
                        Image(systemName: AgentKind.symbol(session.agentId))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AgentKind.tint(session.agentId))
                    }
                }
            }
            .frame(width: 22, height: 22)
            .help(AgentKind.name(session.agentId))

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                // Software name + context-usage % live together on the subtitle line, kept
                // OUT of the trailing status badge so status and percent never overlap.
                HStack(spacing: 4) {
                    Text(AgentKind.name(session.agentId))
                        .lineLimit(1)
                    if let remain = session.contextRemainingPercent {
                        // "· 50% left" / "· 剩 50%" — % kept literal via %%, number via %@.
                        Text(String(format: NSLocalizedString("· %@%% left", comment: "context remaining"), "\(remain)"))
                            .monospacedDigit()
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

                // Surface the agent's own words: the question while it's waiting (.notification),
                // and its final reply once the task is done (.attention) or errored (.error).
                if let msg = session.lastOutput,
                   !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   session.state == .notification || session.state == .attention || session.state == .error {
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundStyle(session.state == .notification ? .orange.opacity(0.95)
                                         : session.state == .error ? .red.opacity(0.9)
                                         : .white.opacity(0.75))
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 6)

            badge
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping a "needs you" row clears it; otherwise no action (no acknowledge step —
            // state just follows the conversation, like clawd).
            if session.state == .notification { store.dismissNotification(session.id) }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let status = statusBadge {
            pill(text: status.text, color: status.color)
        }
    }

    /// The live status pill, derived purely from the session state (no acknowledge step). It
    /// updates as the conversation progresses: Working → Done → Working again on continue.
    private var statusBadge: (text: LocalizedStringKey, color: Color)? {
        switch session.state {
        case .attention:
            return ("Done", .green)
        case .error:
            return ("Error", .red)
        case .notification:
            return ("Needs you", .orange)
        case .thinking, .working, .juggling, .sweeping, .carrying:
            return ("Working", .blue)
        case .idle, .sleeping:
            return nil
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

            Section("Coding tools") {
                Text("NotchPet reuses clawd-on-desk's ready-made installers to capture tasks from many CLIs/IDEs. Toggle which to hook.")
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
                Toggle("Answer permission requests in NotchPet", isOn: Binding(
                    get: { permissions },
                    set: { coord.setPermissionsEnabled($0) }
                ))
                Text("When on, tool-permission prompts appear as a bubble. When off, Claude Code keeps using its own terminal prompt.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Auto-pilot: approve all requests", isOn: Binding(
                    get: { coord.autoPilotEnabled },
                    set: { coord.setAutoPilotEnabled($0) }
                ))
                .disabled(!permissions)
                .foregroundStyle(coord.autoPilotEnabled ? Color.red : Color.primary)

                Text("Session only. Automatically approves commands, file changes, and clarification prompts; it turns off when NotchPet quits.")
                    .font(.caption)
                    .foregroundStyle(coord.autoPilotEnabled ? .red : .secondary)

                Text("ChatGPT/Codex desktop tasks keep using the permission mode selected in ChatGPT; their log monitor exposes status, but not an approval response channel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { coord.refreshHookStatus() }
    }
}
