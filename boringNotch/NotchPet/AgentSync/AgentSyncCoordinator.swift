//
//  AgentSyncCoordinator.swift
//  NotchPet — AI coding-agent task sync
//
//  Top-level owner: starts/stops the listener, installs hooks, writes the runtime
//  port file, and turns completion/error events into a system notification + a
//  closed-notch peek. Also drives the optional desktop pet.
//

import SwiftUI
import AppKit
import Defaults

extension Defaults.Keys {
    static let agentSyncEnabled = Key<Bool>("notchpet.agentsync.enabled", default: true)
    static let agentCompletionNotification = Key<Bool>("notchpet.agentsync.completionNotification", default: true)
    static let agentCompletionSound = Key<Bool>("notchpet.agentsync.completionSound", default: true)
    static let agentPermissionsEnabled = Key<Bool>("notchpet.agentsync.permissionsEnabled", default: true)
    static let agentPetEnabled = Key<Bool>("notchpet.agentsync.petEnabled", default: true)
    static let agentShowInClosedNotch = Key<Bool>("notchpet.agentsync.showInClosedNotch", default: true)
}

@MainActor
final class AgentSyncCoordinator: ObservableObject {
    static let shared = AgentSyncCoordinator()

    private let listener = AgentHTTPListener()

    @Published private(set) var running = false
    @Published private(set) var activePort: UInt16?
    @Published var lastInstallMessage = ""
    @Published var hooksInstalled = false

    /// A just-completed/errored session to flash in the closed notch.
    @Published var completionPeek: AgentSession?
    private var peekTask: Task<Void, Never>?

    /// A pending tool-permission request, shown INSIDE the expanded notch (Allow/Deny).
    @Published var pendingPermission: PendingPermission?
    private var permissionTimeout: Task<Void, Never>?

    /// Danger-gated and intentionally ephemeral: always resets to false when the app relaunches.
    @Published private(set) var autoPilotEnabled = false

    /// A pending AskUserQuestion (questionnaire) — answered IN the notch (or deferred to terminal).
    @Published var pendingClarification: PendingClarification?
    private var clarificationTimeout: Task<Void, Never>?

    /// Incremented after an answer submitted from the notch is accepted. ContentView observes this
    /// separately from `pendingClarification` so a click-to-submit can retract the notch even while
    /// the pointer is still inside its hover region.
    @Published private(set) var clarificationSubmitCompletion = 0

    /// The clarification card's measured natural height (reported by the view), so the notch can
    /// size to exactly fit it — uniform margins, no inner gap, no scroll.
    @Published var clarificationCardHeight: CGFloat = 0

    private init() {}

    /// Called at app launch.
    func startIfEnabled() {
        if Defaults[.agentSyncEnabled] { start() }
    }

    func start() {
        guard !running else { return }
        running = true
        NotificationManager.shared.requestAuthorizationIfNeeded()

        listener.onPortBound = { [weak self] port in
            Task { @MainActor in
                guard let self else { return }
                self.activePort = port
                await HookInstaller.writeRuntime(port: port)
                // Claude Code: install clawd's SELF-CONTAINED vendored hook (np-clawd-hook.js under
                // ~/.notchpet) — gives real conversation titles, context-usage and one stable
                // session per conversation, WITHOUT the Clawd app. Also strips any clawd-app
                // leftovers (incl. auto-start). Runs every launch so it self-heals.
                _ = await MultiAgentInstaller.installClaude()
                self.hooksInstalled = await HookInstaller.isInstalled()
            }
        }
        listener.onCodexUserInputRequest = { [weak self] sessionId, callId, requestId, requestIdType, questions, headless in
            Task { @MainActor in
                self?.presentCodexUserInput(sessionId: sessionId, callId: callId,
                                            requestId: requestId, requestIdType: requestIdType,
                                            questions: questions, headless: headless)
            }
        }
        listener.onCodexUserInputResolved = { [weak self] sessionId, callId in
            Task { @MainActor in self?.dismissCodexUserInput(sessionId: sessionId, callId: callId) }
        }
        configurePermissionHandling(enabled: Defaults[.agentPermissionsEnabled])
        listener.start()
        // The pet lives INSIDE the notch (see AgentLiveActivity / AgentPetView),
        // so there is no floating desktop window to show/hide here.

        // Install hooks for the OTHER coding tools (Codex/Cursor/Gemini/…) via clawd-on-desk's
        // vendored installers (once). Claude Code is handled above by HookInstaller and needs
        // no clawd dependency.
        Task {
            await MultiAgentInstaller.installIfNeeded()
            // Desktop apps (Codex …) don't fire hooks — start their session-log monitors so
            // they show up while executing, not just CLI tools.
            await MultiAgentInstaller.startMonitors()
        }
    }

    private func configurePermissionHandling(enabled: Bool) {
        if enabled {
            listener.onPermission = { [weak self] payload, respond in
                Task { @MainActor in
                    guard let self else {
                        respond(.wait)
                        return
                    }
                    if self.autoPilotEnabled {
                        if self.canAutoApprove(payload) {
                            respond(.allow)
                            AgentSessionStore.shared.clearNotificationAlerts()
                        } else {
                            // Preserve the agent's native fallback for background/subagent work.
                            respond(.wait)
                        }
                        return
                    }
                    self.presentPermission(payload, respond: respond)
                }
            }
            // AskUserQuestion answered in the notch (uses the same PermissionRequest hook).
            listener.onClarification = { [weak self] clar in
                Task { @MainActor in self?.presentClarification(clar) }
            }
        } else {
            listener.onPermission = nil
            listener.onClarification = nil

            permissionTimeout?.cancel()
            pendingPermission?.respond(.wait)
            pendingPermission = nil

            clarificationTimeout?.cancel()
            pendingClarification?.goToTerminal()
            pendingClarification = nil
            clarificationCardHeight = 0
        }
    }

    func reinstallAllAgents() {
        Task { await MultiAgentInstaller.installEnabled() }
    }

    func stop() {
        running = false
        listener.stop()
    }

    func setEnabled(_ on: Bool) {
        Defaults[.agentSyncEnabled] = on
        if on { start() } else { stop() }
    }

    func setPermissionsEnabled(_ on: Bool) {
        Defaults[.agentPermissionsEnabled] = on
        if !on { autoPilotEnabled = false }
        configurePermissionHandling(enabled: on)
    }

    /// Enable/disable automatic approval for this app process only. Enabling also consumes any
    /// already-visible request so a task does not remain blocked after the user confirms the mode.
    func setAutoPilotEnabled(_ on: Bool) {
        guard autoPilotEnabled != on else { return }

        if on, !Defaults[.agentPermissionsEnabled] {
            Defaults[.agentPermissionsEnabled] = true
        }
        autoPilotEnabled = on
        configurePermissionHandling(enabled: Defaults[.agentPermissionsEnabled])

        guard on else { return }
        if let pendingPermission {
            resolvePermission(canAutoApprove(pendingPermission.payload) ? .allow : .wait)
        }
        if let pendingClarification {
            resolveClarificationForAutoPilot(pendingClarification)
        }
    }

    func reinstallHooks() {
        Task { @MainActor in
            lastInstallMessage = "Reinstalling hooks…"
            if let port = activePort { await HookInstaller.writeRuntime(port: port) }
            _ = await MultiAgentInstaller.installClaude()
            await MultiAgentInstaller.installEnabled()
            lastInstallMessage = "Hooks reinstalled (self-contained — no clawd app needed)."
            hooksInstalled = await HookInstaller.isInstalled()
        }
    }

    func removeHooks() {
        Task { @MainActor in
            let r = await HookInstaller.uninstall()
            lastInstallMessage = r.message
            hooksInstalled = await HookInstaller.isInstalled()
        }
    }

    func refreshHookStatus() {
        Task { @MainActor in hooksInstalled = await HookInstaller.isInstalled() }
    }

    /// Toggle whether the reactive crab pet is shown inside the notch's live activity
    /// (vs. a plain state icon). Purely a rendering preference — read by AgentLiveActivity.
    func setPetEnabled(_ on: Bool) {
        Defaults[.agentPetEnabled] = on
    }

    // MARK: - Side effects

    func handleCompletion(_ s: AgentSession) {
        if Defaults[.agentCompletionNotification] {
            let body = s.lastOutput.map { String($0.prefix(140)) } ?? "Task finished."
            NotificationManager.shared.schedule(
                id: "notchpet.agent.done.\(s.id)",
                title: "✅ \(s.title)",
                body: body,
                after: 0.1,
                sound: Defaults[.agentCompletionSound])
        }
        flashPeek(s)
    }

    func handleError(_ s: AgentSession) { flashPeek(s) }

    func handleClarification(_ s: AgentSession) {
        if Defaults[.agentCompletionNotification] {
            NotificationManager.shared.schedule(
                id: "notchpet.agent.ask.\(s.id)",
                title: "🟠 \(s.title)",
                body: "Needs your input.",
                after: 0.1,
                sound: Defaults[.agentCompletionSound])
        }
        // No timed peek: the closed-notch clarification indicator persists (driven by the
        // session's .notification state) until the user handles it and the agent moves on.
    }

    private func flashPeek(_ s: AgentSession) {
        guard Defaults[.agentShowInClosedNotch] else { return }
        completionPeek = s
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run { self?.completionPeek = nil }
        }
    }

    private func presentPermission(_ payload: PermissionRequestPayload, respond: @escaping (PermissionDecision) -> Void) {
        // Show the request INSIDE the notch (ContentView auto-expands on this), not a floating bubble.
        pendingPermission = PendingPermission(payload: payload, respond: respond)
        permissionTimeout?.cancel()
        permissionTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(600))   // matches the hook timeout
            await MainActor.run { self?.pendingPermission = nil }
        }
    }

    private func canAutoApprove(_ payload: PermissionRequestPayload) -> Bool {
        !payload.isHeadless && !AgentSessionStore.shared.isHeadlessSession(payload.sessionId)
    }

    /// Resolve the pending permission (called by the in-notch Allow/Deny buttons).
    func resolvePermission(_ decision: PermissionDecision) {
        permissionTimeout?.cancel()
        pendingPermission?.respond(decision)
        pendingPermission = nil
        // Allowing/denying also ends any lingering "needs you" alert for the same prompt.
        AgentSessionStore.shared.clearNotificationAlerts()
    }

    // MARK: - Clarification (AskUserQuestion answered in the notch)

    func presentClarification(_ c: PendingClarification) {
        if autoPilotEnabled && !c.isReadOnly {
            resolveClarificationForAutoPilot(c)
            return
        }
        clarificationCardHeight = 0   // start fresh; the card re-measures and the notch sizes to it
        pendingClarification = c
        clarificationTimeout?.cancel()
        if c.isReadOnly { return }
        clarificationTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(590))   // just under the 600s hook timeout
            await MainActor.run { self?.pendingClarification = nil }
        }
    }

    private func resolveClarificationForAutoPilot(_ c: PendingClarification) {
        guard !c.isReadOnly else {
            presentClarification(c)
            return
        }
        guard !c.headless, !AgentSessionStore.shared.isHeadlessSession(c.sessionId) else {
            c.goToTerminal()
            pendingClarification = nil
            return
        }
        var answers: [String: String] = [:]
        for question in c.questions where !question.question.isEmpty {
            answers[question.question] = "You choose whatever is best."
        }
        guard !answers.isEmpty else {
            c.goToTerminal()
            pendingClarification = nil
            return
        }
        clarificationTimeout?.cancel()
        c.submit(answers)
        pendingClarification = nil
        clarificationCardHeight = 0
        AgentSessionStore.shared.clearNotificationAlerts()
    }

    /// Submit the user's answers (label per question text) back to Claude Code via the hook.
    func resolveClarification(_ answers: [String: String]) {
        clarificationTimeout?.cancel()
        guard let clarification = pendingClarification else { return }
        clarification.submit(answers)
        if clarification.isReadOnly {
            // A bridge-backed Codex prompt is cleared by the submit completion callback only after
            // the helper successfully writes the JSON-RPC response. Legacy log-only prompts have no
            // request id, so retain the exact-task fallback for those.
            if clarification.externalRequestId == nil { clarification.goToTerminal() }
            return
        }
        pendingClarification = nil
        clarificationCardHeight = 0
        clarificationSubmitCompletion &+= 1
        AgentSessionStore.shared.clearNotificationAlerts()
    }

    /// The clarification was answered/closed elsewhere (e.g. in the terminal) — clear the notch card.
    func dismissClarification(id: UUID) {
        guard pendingClarification?.id == id else { return }
        clarificationTimeout?.cancel()
        pendingClarification = nil
        clarificationCardHeight = 0
        AgentSessionStore.shared.clearNotificationAlerts()
    }

    /// The clarification for this session progressed (it was answered elsewhere, e.g. the terminal,
    /// so the agent resumed) — clear the notch card.
    func dismissClarification(forSession sessionId: String) {
        guard pendingClarification?.sessionId == sessionId else { return }
        clarificationTimeout?.cancel()
        pendingClarification = nil
        clarificationCardHeight = 0
        AgentSessionStore.shared.clearNotificationAlerts()
    }

    private func presentCodexUserInput(sessionId: String, callId: String,
                                       requestId: String?, requestIdType: String?,
                                       questions: [ClarificationQuestion], headless: Bool) {
        guard !headless else { return }
        if let current = pendingClarification,
           current.sessionId == sessionId, current.externalCallId == callId,
           current.externalRequestId != nil, requestId == nil {
            return
        }
        let clarification = PendingClarification(
            sessionId: sessionId,
            title: "Codex",
            questions: questions,
            headless: false,
            submit: { [weak self] answers in
                guard let requestId else { return }
                Task {
                    let submitted = await Self.submitCodexAnswers(
                        requestId: requestId,
                        requestIdType: requestIdType,
                        answers: answers)
                    await MainActor.run {
                        self?.finishCodexUserInputSubmission(
                            sessionId: sessionId,
                            callId: callId,
                            requestId: requestId,
                            succeeded: submitted)
                    }
                }
            },
            goToTerminal: { Self.openCodexThread(sessionId: sessionId) },
            isReadOnly: true,
            externalCallId: callId,
            externalRequestId: requestId)
        presentClarification(clarification)
    }

    private func dismissCodexUserInput(sessionId: String, callId: String) {
        guard pendingClarification?.sessionId == sessionId,
              pendingClarification?.externalCallId == callId else { return }
        clarificationTimeout?.cancel()
        pendingClarification = nil
        clarificationCardHeight = 0
    }

    private func finishCodexUserInputSubmission(sessionId: String, callId: String,
                                                requestId: String, succeeded: Bool) {
        guard let current = pendingClarification,
              current.sessionId == sessionId,
              current.externalCallId == callId,
              current.externalRequestId == requestId else { return }
        guard succeeded else {
            lastInstallMessage = "Could not submit the Codex answer. Please try again."
            return
        }
        clarificationTimeout?.cancel()
        pendingClarification = nil
        clarificationCardHeight = 0
        clarificationSubmitCompletion &+= 1
        AgentSessionStore.shared.clearNotificationAlerts()
    }

    private static func openCodexThread(sessionId: String) {
        let threadId = sessionId.hasPrefix("codex:")
            ? String(sessionId.dropFirst("codex:".count))
            : sessionId
        guard UUID(uuidString: threadId) != nil else {
            let candidates = ["/Applications/ChatGPT.app", "/Applications/Codex.app"]
            guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration())
            return
        }

        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(threadId)"
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    private static func submitCodexAnswers(requestId: String, requestIdType: String?,
                                           answers: [String: String]) async -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: answers),
              let json = String(data: data, encoding: .utf8) else { return false }
        let script = MultiAgentInstaller.clawdDir + "/hooks/codex-app-server-answer.js"
        let (code, _) = await XPCHelperClient.shared.runNotchpetNode(
            script, args: [requestIdType == "number" ? "number" : "string", requestId, json])
        return code == 0
    }

    /// The permission request was resolved elsewhere — clear the notch card.
    func dismissPermission(requestId: UUID) {
        guard pendingPermission?.payload.requestId == requestId else { return }
        permissionTimeout?.cancel()
        pendingPermission = nil
        AgentSessionStore.shared.clearNotificationAlerts()
    }

    /// The pending permission for this session was answered elsewhere (e.g. the user allowed/denied
    /// in the terminal). Called ONLY from post-resolution events (PostToolUse / Stop / …), never from
    /// the concurrent PreToolUse that raised the request — otherwise the card would kill itself the
    /// instant it appears. The session-keyed guard makes it a no-op for unrelated sessions.
    func dismissPermission(forSession sessionId: String) {
        guard pendingPermission?.payload.sessionId == sessionId else { return }
        permissionTimeout?.cancel()
        pendingPermission = nil
        AgentSessionStore.shared.clearNotificationAlerts()
    }

    /// Defer to the terminal — Claude Code shows its own questionnaire there.
    func clarificationToTerminal() {
        if let clarification = pendingClarification, clarification.isReadOnly {
            clarification.goToTerminal()
            return
        }
        clarificationTimeout?.cancel()
        pendingClarification?.goToTerminal()
        pendingClarification = nil
        AgentSessionStore.shared.clearNotificationAlerts()
    }
}

/// One question of an AskUserQuestion prompt.
struct ClarificationOption: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let description: String
}

struct ClarificationQuestion: Identifiable {
    let id = UUID()
    let question: String
    let header: String
    let options: [ClarificationOption]
    let multiSelect: Bool
    let allowsOther: Bool
    let answerKey: String

    init(question: String, header: String, options: [ClarificationOption],
         multiSelect: Bool, allowsOther: Bool = true, answerKey: String? = nil) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
        self.allowsOther = allowsOther
        self.answerKey = answerKey ?? question
    }
}

/// A pending AskUserQuestion shown in the notch. `submit` sends the chosen answers back to Claude
/// Code (via the PermissionRequest hook's updatedInput.answers); `goToTerminal` defers to its UI.
struct PendingClarification: Identifiable {
    var id = UUID()
    let sessionId: String
    let title: String
    let questions: [ClarificationQuestion]
    let headless: Bool
    let submit: ([String: String]) -> Void   // [question text: answer string]
    let goToTerminal: () -> Void
    let isReadOnly: Bool
    let externalCallId: String?
    let externalRequestId: String?

    init(id: UUID = UUID(), sessionId: String, title: String,
         questions: [ClarificationQuestion], headless: Bool,
         submit: @escaping ([String: String]) -> Void,
         goToTerminal: @escaping () -> Void,
         isReadOnly: Bool = false, externalCallId: String? = nil,
         externalRequestId: String? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.title = title
        self.questions = questions
        self.headless = headless
        self.submit = submit
        self.goToTerminal = goToTerminal
        self.isReadOnly = isReadOnly
        self.externalCallId = externalCallId
        self.externalRequestId = externalRequestId
    }
}

/// A tool-permission request awaiting the user's Allow/Deny inside the notch.
struct PendingPermission: Identifiable {
    let id = UUID()
    let payload: PermissionRequestPayload
    let respond: (PermissionDecision) -> Void
}
