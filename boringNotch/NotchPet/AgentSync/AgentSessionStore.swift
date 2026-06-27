//
//  AgentSessionStore.swift
//  NotchPet — AI coding-agent task sync
//
//  Tracks concurrent agent sessions, arbitrates the displayed state across them,
//  and fires completion side-effects (notification + closed-notch peek).
//

import SwiftUI

@MainActor
final class AgentSessionStore: ObservableObject {
    static let shared = AgentSessionStore()

    @Published private(set) var sessions: [String: AgentSession] = [:]
    @Published private(set) var displayState: AgentState = .idle
    @Published private(set) var displaySession: AgentSession?

    private let maxSessions = 20
    private var cleanupTimer: Timer?

    private init() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pruneStale() }
        }
    }

    /// Number of concurrently working sessions (for pet/indicator tier-up).
    var workingTier: Int { sessions.values.filter { $0.state == .working || $0.state == .juggling }.count }

    /// True while any session is actively progressing (for the closed-notch arbiter).
    var hasActiveWork: Bool {
        sessions.values.contains { [.thinking, .working, .juggling, .sweeping, .notification].contains($0.state) }
    }

    /// Sessions sorted for the Agents tab: just-completed (unacked) pinned to the very
    /// top, then everything else newest-first.
    var orderedSessions: [AgentSession] {
        sessions.values.sorted {
            if $0.requiresAck != $1.requiresAck { return $0.requiresAck && !$1.requiresAck }
            return $0.updatedAt > $1.updatedAt
        }
    }

    /// Most recent live session for an agent, used to coalesce stray events that arrive
    /// without a usable session_id (avoids one conversation splitting into two rows).
    private func coalesceKey(forAgent agentId: String) -> String? {
        sessions.values
            .filter { $0.agentId == agentId && Date().timeIntervalSince($0.updatedAt) < 120 }
            .max(by: { $0.updatedAt < $1.updatedAt })?.id
    }

    func ingest(event: String, payload: AgentEvent, agentIdOverride: String? = nil) {
        let agentId = agentIdOverride ?? payload.agentId ?? "claude-code"
        let newState = AgentStateMachine.state(forEvent: event, payload: payload)

        // Robust session key: use the real session_id; if missing/"default", attach to the
        // agent's most-recent live session; otherwise fall back to agent+cwd.
        let raw = payload.sessionId
        let sid: String
        if let r = raw, !r.isEmpty, r != "default" {
            sid = r
        } else if let recent = coalesceKey(forAgent: agentId) {
            sid = recent
        } else {
            sid = "\(agentId)|\(payload.cwd ?? "default")"
        }

        if event == "SessionEnd" {
            sessions[sid] = nil
            recomputeDisplay()
            return
        }

        var s = sessions[sid] ?? AgentSession(
            id: sid,
            agentId: agentId,
            state: .idle,
            title: "",
            contextPercent: nil,
            lastOutput: nil,
            cwd: nil,
            headless: false,
            updatedAt: Date(),
            requiresAck: false
        )

        s.agentId = agentId
        // Prefer the real conversation title computed by the hook; only fall back to the
        // folder name when we still have nothing.
        if let t = payload.sessionTitle, !t.isEmpty { s.title = t }
        if s.title.isEmpty {
            s.title = (payload.cwd as NSString?)?.lastPathComponent ?? AgentKind.name(agentId)
        }
        if let pct = payload.contextUsage?.percent { s.contextPercent = pct }
        if let cwd = payload.cwd { s.cwd = cwd }
        if let h = payload.headless { s.headless = h }
        if let out = payload.assistantLastOutput, !out.isEmpty { s.lastOutput = out }
        s.state = newState
        s.updatedAt = Date()

        let justCompleted = (newState == .attention)
        if justCompleted { s.requiresAck = true }

        sessions[sid] = s
        enforceCapacity()
        recomputeDisplay()

        if justCompleted, !s.headless {
            AgentSyncCoordinator.shared.handleCompletion(s)
        } else if newState == .error {
            AgentSyncCoordinator.shared.handleError(s)
        } else if newState == .notification {
            // Agent needs the user (permission prompt / AskUserQuestion / clarification).
            AgentSyncCoordinator.shared.handleClarification(s)
        }
    }

    func ack(_ id: String) {
        sessions[id]?.requiresAck = false
        recomputeDisplay()
    }

    func clearAll() {
        sessions.removeAll()
        recomputeDisplay()
    }

    private func enforceCapacity() {
        guard sessions.count > maxSessions else { return }
        // Evict oldest non-ack sessions first.
        let evictable = sessions.values
            .filter { !$0.requiresAck }
            .sorted { $0.updatedAt < $1.updatedAt }
        var overflow = sessions.count - maxSessions
        for s in evictable where overflow > 0 {
            sessions[s.id] = nil
            overflow -= 1
        }
    }

    private func pruneStale() {
        let cutoff = Date().addingTimeInterval(-300) // 5 min TTL
        let before = sessions.count
        sessions = sessions.filter { $0.value.updatedAt > cutoff || $0.value.requiresAck }
        if sessions.count != before { recomputeDisplay() }
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
