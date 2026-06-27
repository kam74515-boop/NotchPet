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
        case .idle: return String(localized: "Idle")
        case .thinking: return String(localized: "Thinking")
        case .working: return String(localized: "Working")
        case .juggling: return String(localized: "Subagents")
        case .sweeping: return String(localized: "Compacting")
        case .error: return String(localized: "Error")
        case .attention: return String(localized: "Done")
        case .notification: return String(localized: "Needs you")
        case .carrying: return String(localized: "Working")
        case .sleeping: return String(localized: "Asleep")
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

/// Identity (name / icon / color) for each coding tool, so the Agents list shows which
/// software a session belongs to.
enum AgentKind {
    static func name(_ id: String) -> String {
        switch id {
        case "claude-code": return "Claude Code"
        case "codex": return "Codex"
        case "cursor", "cursor-agent": return "Cursor"
        case "copilot", "copilot-cli": return "Copilot"
        case "gemini", "gemini-cli": return "Gemini"
        case "qwen", "qwen-code": return "Qwen"
        case "opencode": return "opencode"
        case "kiro", "kiro-cli": return "Kiro"
        case "codebuddy": return "CodeBuddy"
        default: return id.isEmpty ? "Agent" : id
        }
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "claude-code": return "sparkle"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "cursor", "cursor-agent": return "cursorarrow.rays"
        case "copilot", "copilot-cli": return "person.2.fill"
        case "gemini", "gemini-cli": return "diamond.fill"
        case "qwen", "qwen-code": return "q.circle.fill"
        case "opencode": return "curlybraces"
        default: return "cpu"
        }
    }

    static func tint(_ id: String) -> Color {
        switch id {
        case "claude-code": return Color(red: 0.85, green: 0.45, blue: 0.25) // Claude orange
        case "codex": return Color(red: 0.10, green: 0.65, blue: 0.45)        // OpenAI green
        case "cursor", "cursor-agent": return .blue
        case "copilot", "copilot-cli": return .gray
        case "gemini", "gemini-cli": return .purple
        case "qwen", "qwen-code": return .indigo
        default: return .teal
        }
    }
}
