//
//  AgentSessionStore.swift
//  NotchPet — AI coding-agent task sync
//
//  Mirrors clawd-on-desk's model: one session per session_id, whose STATE simply follows the
//  events (working → done → working again on continue). No "acknowledge" step — completion just
//  shows as done, and continuing the conversation updates the same row. The notch UI is the only
//  thing that differs from clawd.
//

import SwiftUI
import Defaults

extension Defaults.Keys {
    /// Recently-seen sessions, persisted so they survive an app restart.
    static let persistedCompletedSessions = Key<[AgentSession]>("notchpet.agentsync.completedSessions", default: [])
}

@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    @Published private(set) var sessions: [String: AgentSession] = [:]
    @Published private(set) var displayState: AgentState = .idle
    @Published private(set) var displaySession: AgentSession?

    private let maxSessions = 24
    private var cleanupTimer: Timer?

    private init() {
        // Restore recent sessions so they survive a restart (drop legacy ones from older builds
        // that have no transcript — their titles were folder names we can't fix).
        for s in Defaults[.persistedCompletedSessions] where s.transcriptPath != nil {
            sessions[s.id] = s
        }
        recomputeDisplay()
        persistRecent()
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStale() }
        }
    }

    /// Persist the most recent sessions (by last update) so they survive a restart.
    private func persistRecent() {
        let recent = sessions.values.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxSessions)
        Defaults[.persistedCompletedSessions] = Array(recent)
    }

    /// Number of concurrently working sessions (for pet/indicator tier-up).
    var workingTier: Int { sessions.values.filter { $0.state == .working || $0.state == .juggling }.count }

    /// True while any session is actively progressing (for the closed-notch arbiter).
    var hasActiveWork: Bool {
        sessions.values.contains { [.thinking, .working, .juggling, .sweeping, .notification].contains($0.state) }
    }

    /// Display order: needs-you first, then actively-working, then just-done/error, then idle —
    /// each group newest-first. One row per session.
    var orderedSessions: [AgentSession] {
        sessions.values.sorted {
            let r0 = Self.activityRank($0.state), r1 = Self.activityRank($1.state)
            return r0 != r1 ? r0 < r1 : $0.updatedAt > $1.updatedAt
        }
    }

    /// Auto-pilot must never approve requests for background/subagent sessions.
    func isHeadlessSession(_ id: String) -> Bool { sessions[id]?.headless == true }

    private static func activityRank(_ s: AgentState) -> Int {
        switch s {
        case .notification: return 0
        case .working, .thinking, .juggling, .sweeping, .carrying: return 1
        case .attention, .error: return 2
        case .idle, .sleeping: return 3
        }
    }

    func ingest(event: String, payload: AgentEvent, agentIdOverride: String? = nil) {
        let agentId = agentIdOverride ?? payload.agentId ?? "claude-code"
        // Use the state clawd's hook already computed (it correctly classifies clarification /
        // questionnaire as "notification", etc.); only fall back to our own event→state map when
        // the hook didn't send a recognizable state.
        var newState = payload.state.flatMap { AgentState(rawValue: $0) }
            ?? AgentStateMachine.state(forEvent: event, payload: payload)

        // Interactive "ask the user" tools block for input — clawd reports them as plain "working",
        // but they're really a clarification. Detect them reliably on PreToolUse by tool name
        // (the hook always sends tool_name; it does NOT send the question text, only a fingerprint).
        var clarificationMessage: String?
        if let tool = payload.toolName {
            if event == "PreToolUse", tool == "AskUserQuestion" || tool == "ExitPlanMode" {
                newState = .notification
                clarificationMessage = tool == "ExitPlanMode" ? String(localized: "Please review and approve the plan") : String(localized: "Asking you a question (AskUserQuestion)")
            } else if agentId == "codex", newState == .notification {
                clarificationMessage = tool == "request_user_input"
                    ? String(format: String(localized: "Asking you a question (%@)"), "Codex")
                    : String(localized: "Permission request")
            }
        }

        // Key strictly by session_id, exactly like clawd (its hooks always send one, "default"
        // when absent). No "smart" coalescing — that caused both missing tasks (events merged
        // into the wrong row) and duplicates (a cwd-keyed row plus a session_id-keyed row).
        let sid = (payload.sessionId?.isEmpty == false) ? payload.sessionId! : "default"

        if event == "SessionEnd" {
            sessions[sid] = nil
            recomputeDisplay()
            AgentSyncCoordinator.shared.dismissPermission(forSession: sid)
            return
        }

        var s = sessions[sid] ?? AgentSession(
            id: sid, agentId: agentId, state: .idle, title: "",
            contextPercent: nil, lastOutput: nil, cwd: nil, headless: false,
            updatedAt: Date(), transcriptPath: nil, contextUsed: nil, contextLimit: nil
        )

        s.agentId = agentId
        if let tp = payload.transcriptPath, !tp.isEmpty { s.transcriptPath = tp }
        if let t = payload.sessionTitle, !t.isEmpty { s.title = t }
        if s.title.isEmpty {
            s.title = (payload.cwd as NSString?)?.lastPathComponent ?? AgentKind.name(agentId)
        }
        if let pct = payload.contextUsage?.percent { s.contextPercent = pct }
        if let u = payload.contextUsage?.used { s.contextUsed = u }
        if let l = payload.contextUsage?.limit { s.contextLimit = l }
        if let cwd = payload.cwd { s.cwd = cwd }
        if let h = payload.headless { s.headless = h }
        if let out = payload.assistantLastOutput, !out.isEmpty { s.lastOutput = out }
        if let cm = clarificationMessage { s.lastOutput = cm }
        s.state = newState
        s.updatedAt = Date()

        sessions[sid] = s
        enforceCapacity()
        recomputeDisplay()

        // If a clarification card is showing in the notch for THIS session and the session has now
        // moved on (e.g. the question was answered in the terminal, so the agent resumed or fired
        // PostToolUse), dismiss the card so it doesn't linger as "already answered".
        // Any progress event for this session that isn't itself the "needs you" state means the
        // question is no longer pending (answered, or the agent stopped). The session-keyed guard
        // inside dismiss makes this a no-op for unrelated sessions.
        if newState != .notification {
            AgentSyncCoordinator.shared.dismissClarification(forSession: sid)
        }

        // A pending in-notch PERMISSION card is a separate matter: unlike a clarification, the
        // session state stays "working" while it's pending, so we can't key off state. The card must
        // survive its OWN raising event — the PreToolUse that needs permission fires a concurrent
        // "working" /event, and a terminal "Claude needs permission" Notification also arrives while
        // it's still pending. Only a POST-resolution event means the user answered elsewhere: the
        // tool actually ran (PostToolUse), the turn ended (Stop), a new prompt began, or the session
        // ended. Dismiss the card on those, never on PreToolUse/Notification.
        switch event {
        case "PostToolUse", "Stop", "UserPromptSubmit":
            AgentSyncCoordinator.shared.dismissPermission(forSession: sid)
        default:
            break
        }

        // Side effects on transitions (notification + closed-notch peek).
        if newState == .attention, !s.headless {
            AgentSyncCoordinator.shared.handleCompletion(s)
        } else if newState == .error {
            AgentSyncCoordinator.shared.handleError(s)
        } else if newState == .notification {
            AgentSyncCoordinator.shared.handleClarification(s)
        }
        persistRecent()
    }

    /// An interactive "ask the user" tool (AskUserQuestion / ExitPlanMode) is waiting — reflect it
    /// as a clarification (Needs you + the question) instead of an allow/deny permission card.
    func markClarification(sessionId: String, tool: String, question: String?) {
        var s = sessions[sessionId] ?? AgentSession(
            id: sessionId, agentId: "claude-code", state: .notification, title: "",
            contextPercent: nil, lastOutput: nil, cwd: nil, headless: false,
            updatedAt: Date(), transcriptPath: nil, contextUsed: nil, contextLimit: nil)
        s.state = .notification
        if let q = question, !q.isEmpty {
            s.lastOutput = q
        } else if (s.lastOutput?.isEmpty ?? true) {
            s.lastOutput = String(localized: "Asking you a question (\(tool))")
        }
        if s.title.isEmpty { s.title = AgentKind.name(s.agentId) }
        s.updatedAt = Date()
        sessions[sessionId] = s
        recomputeDisplay()
        AgentSyncCoordinator.shared.handleClarification(s)
    }

    /// Dismiss a single "needs you" (notification) alert — removes the row; a later event for the
    /// same session re-creates it.
    func dismissNotification(_ id: String) {
        guard sessions[id]?.state == .notification else { return }
        sessions[id] = nil
        recomputeDisplay()
    }

    /// Clear pending "needs you" alerts — called after the user answers a permission prompt.
    func clearNotificationAlerts() {
        let ids = sessions.filter { $0.value.state == .notification }.map(\.key)
        guard !ids.isEmpty else { return }
        for id in ids {
            sessions[id]?.state = .idle
            sessions[id]?.updatedAt = Date()
        }
        recomputeDisplay()
    }

    func clearAll() {
        sessions.removeAll()
        Defaults[.persistedCompletedSessions] = []
        recomputeDisplay()
    }

    private func enforceCapacity() {
        guard sessions.count > maxSessions else { return }
        let overflow = sessions.count - maxSessions
        let oldest = sessions.values.sorted { $0.updatedAt < $1.updatedAt }.prefix(overflow)
        for s in oldest { sessions[s.id] = nil }
    }

    private func pruneStale() {
        // Active sessions keep updating, so they stay. Dormant (idle/sleeping) ones age out fast
        // so a continued conversation's old session_id doesn't linger next to the new active row;
        // done/error keep a bit of history.
        let now = Date()
        let before = sessions.count
        sessions = sessions.filter { (_, s) in
            let age = now.timeIntervalSince(s.updatedAt)
            switch s.state {
            case .idle, .sleeping: return age < 180    // 3 min
            default:               return age < 1800   // 30 min
            }
        }
        if sessions.count != before { recomputeDisplay(); persistRecent() }
    }

    private func recomputeDisplay() {
        let live = sessions.values.filter { !$0.headless }
        if let best = live.max(by: { $0.state.priority < $1.state.priority }) {
            displayState = best.state
            displaySession = best
        } else {
            displayState = .idle
            displaySession = nil
        }
    }
}
