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

    func ingest(event: String, payload: AgentEvent, agentIdOverride: String? = nil) {
        let sid = payload.sessionId ?? "default"
        let newState = AgentStateMachine.state(forEvent: event, payload: payload)

        if event == "SessionEnd" {
            sessions[sid] = nil
            recomputeDisplay()
            return
        }

        var s = sessions[sid] ?? AgentSession(
            id: sid,
            agentId: agentIdOverride ?? payload.agentId ?? "claude-code",
            state: .idle,
            title: "",
            contextPercent: nil,
            lastOutput: nil,
            cwd: nil,
            headless: false,
            updatedAt: Date(),
            requiresAck: false
        )

        s.agentId = agentIdOverride ?? payload.agentId ?? s.agentId
        if let t = payload.sessionTitle, !t.isEmpty { s.title = t }
        if s.title.isEmpty {
            s.title = (payload.cwd as NSString?)?.lastPathComponent ?? "Claude Code"
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
