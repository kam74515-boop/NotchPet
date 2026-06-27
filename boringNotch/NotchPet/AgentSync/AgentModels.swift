//
//  AgentModels.swift
//  NotchPet — AI coding-agent task sync
//
//  Swift re-implementation of clawd-on-desk's event/state model. The notch and the
//  desktop pet react to AI coding agents (Claude Code, etc.) in real time.
//

import SwiftUI

/// Animation/display states, mirroring clawd's state set.
enum AgentState: String, Codable {
    case idle, thinking, working, juggling, sweeping, error, attention, notification, carrying, sleeping

    /// Multi-session arbitration priority (from clawd state-priority.js — higher wins).
    var priority: Int {
        switch self {
        case .error: return 8
        case .notification: return 7
        case .sweeping: return 6
        case .attention: return 5
        case .carrying, .juggling: return 4
        case .working: return 3
        case .thinking: return 2
        case .idle: return 1
        case .sleeping: return 0
        }
    }

    /// One-shot states get a minimum on-screen time then auto-return to the steady state.
    var isOneshot: Bool {
        switch self {
        case .attention, .error, .sweeping, .notification, .carrying: return true
        default: return false
        }
    }

    var minDisplay: TimeInterval {
        switch self {
        case .attention: return 4
        case .error: return 5
        case .sweeping: return 5.5
        case .notification: return 2.5
        case .carrying: return 3
        default: return 0
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .thinking: return "Thinking"
        case .working: return "Working"
        case .juggling: return "Subagents"
        case .sweeping: return "Compacting"
        case .error: return "Error"
        case .attention: return "Done"
        case .notification: return "Needs you"
        case .carrying: return "Working"
        case .sleeping: return "Asleep"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "moon.zzz"
        case .thinking: return "brain"
        case .working: return "gearshape.2.fill"
        case .juggling: return "circle.hexagongrid.fill"
        case .sweeping: return "wind"
        case .error: return "exclamationmark.triangle.fill"
        case .attention: return "checkmark.circle.fill"
        case .notification: return "bell.badge.fill"
        case .carrying: return "shippingbox.fill"
        case .sleeping: return "zzz"
        }
    }

    var tint: Color {
        switch self {
        case .idle, .sleeping: return .gray
        case .thinking: return .blue
        case .working, .carrying: return .cyan
        case .juggling: return .purple
        case .sweeping: return .teal
        case .error: return .red
        case .attention: return .green
        case .notification: return .orange
        }
    }
}

/// Context-window usage reported by Claude Code.
struct AgentContextUsage: Decodable {
    let used: Int?
    let limit: Int?
    let percent: Double?
}

/// Decoded body of a `POST /state` from the hook script (Claude Code hook payload).
struct AgentEvent: Decodable {
    let event: String?
    let sessionId: String?
    let agentId: String?
    let toolName: String?
    let cwd: String?
    let sessionTitle: String?
    let transcriptPath: String?
    let contextUsage: AgentContextUsage?
    let assistantLastOutput: String?
    let apiErrorType: String?
    let headless: Bool?
    let trigger: String?
    let source: String?
    let backgroundTasksCount: Int?
    let sessionCronsCount: Int?
    let stopHookActive: Bool?

    enum CodingKeys: String, CodingKey {
        case event
        case sessionId = "session_id"
        case agentId = "agent_id"
        case toolName = "tool_name"
        case cwd
        case sessionTitle = "session_title"
        case transcriptPath = "transcript_path"
        case contextUsage = "context_usage"
        case assistantLastOutput = "assistant_last_output"
        case apiErrorType = "api_error_type"
        case headless
        case trigger
        case source
        case backgroundTasksCount = "background_tasks_count"
        case sessionCronsCount = "session_crons_count"
        case stopHookActive = "stop_hook_active"
    }
}

/// A tracked agent session.
struct AgentSession: Identifiable {
    let id: String          // session_id
    var agentId: String
    var state: AgentState
    var title: String
    var contextPercent: Double?
    var lastOutput: String?
    var cwd: String?
    var headless: Bool
    var updatedAt: Date
    var requiresAck: Bool    // completed but not yet acknowledged by the user
}

/// Pure event → state mapping (clawd hooks/clawd-hook.js + Stop/PostCompact rules).
enum AgentStateMachine {
    static func state(forEvent event: String, payload: AgentEvent) -> AgentState {
        switch event {
        case "SessionStart": return .idle
        case "SessionEnd": return (payload.source == "clear") ? .sweeping : .sleeping
        case "UserPromptSubmit": return .thinking
        case "PreToolUse": return (payload.toolName == "Task") ? .juggling : .working
        case "PostToolUse": return .working
        case "PostToolUseFailure": return .error
        case "Stop": return (payload.apiErrorType?.isEmpty == false) ? .error : .attention
        case "StopFailure", "ApiError": return .error
        case "SubagentStart": return .juggling
        case "SubagentStop": return .working
        case "PreCompact": return .sweeping
        case "PostCompact": return (payload.trigger == "manual") ? .idle : .thinking
        case "Notification", "Elicitation": return .notification
        default: return .idle
        }
    }
}
