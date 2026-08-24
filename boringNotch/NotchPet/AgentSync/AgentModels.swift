//
//  AgentModels.swift
//  NotchPet — AI coding-agent task sync
//
//  Swift re-implementation of clawd-on-desk's event/state model. The notch and the
//  desktop pet react to AI coding agents (Claude Code, etc.) in real time.
//

import SwiftUI
import AppKit
import Defaults

/// Animation/display states, mirroring clawd's state set.
enum AgentState: String, Codable {
    case idle, thinking, working, juggling, sweeping, error, attention, notification, carrying, sleeping

    /// Multi-session arbitration for the single closed-notch glance (higher wins). Based on clawd's
    /// state-priority.js, but ACTIVE work outranks a finished task so a lingering "done" session
    /// never masks one that's still generating — otherwise the notch reads green while an agent works.
    var priority: Int {
        switch self {
        case .error: return 9
        case .notification: return 8
        case .working, .juggling, .carrying: return 7
        case .thinking, .sweeping: return 6
        case .attention: return 5
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

/// Lenient JSON helpers so a single unexpected field type never drops the whole event.
private enum Lenient {
    static func string<K>(_ c: KeyedDecodingContainer<K>?, _ k: K) -> String? {
        guard let c else { return nil }
        if let v = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil { return v }
        if let v = (try? c.decodeIfPresent(Int.self, forKey: k)) ?? nil { return String(v) }
        return nil
    }
    static func int<K>(_ c: KeyedDecodingContainer<K>?, _ k: K) -> Int? {
        guard let c else { return nil }
        if let v = (try? c.decodeIfPresent(Int.self, forKey: k)) ?? nil { return v }
        if let v = (try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil { return Int(v) }
        if let v = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil { return Int(v) }
        return nil
    }
    static func double<K>(_ c: KeyedDecodingContainer<K>?, _ k: K) -> Double? {
        guard let c else { return nil }
        if let v = (try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil { return v }
        if let v = (try? c.decodeIfPresent(Int.self, forKey: k)) ?? nil { return Double(v) }
        if let v = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil { return Double(v) }
        return nil
    }
    static func bool<K>(_ c: KeyedDecodingContainer<K>?, _ k: K) -> Bool? {
        guard let c else { return nil }
        if let v = (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? nil { return v }
        if let v = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil { return v == "true" || v == "1" }
        return nil
    }
}

/// Context-window usage reported by Claude Code.
struct AgentContextUsage: Decodable {
    var used: Int?
    var limit: Int?
    var percent: Double?

    enum CodingKeys: String, CodingKey { case used, limit, percent }
    init(from decoder: Decoder) {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        used = Lenient.int(c, .used)
        limit = Lenient.int(c, .limit)
        percent = Lenient.double(c, .percent)
    }
}

/// Decoded body of a `POST /state` from the hook script (Claude Code hook payload). Decoded
/// leniently — a single bad field never drops the whole event.
struct AgentEvent: Decodable {
    var event: String?
    var state: String?          // the state clawd's hook already computed (authoritative)
    var sessionId: String?
    var agentId: String?
    var toolName: String?
    var cwd: String?
    var sessionTitle: String?
    var transcriptPath: String?
    var contextUsage: AgentContextUsage?
    var assistantLastOutput: String?
    var apiErrorType: String?
    var headless: Bool?
    var trigger: String?
    var source: String?
    var backgroundTasksCount: Int?
    var sessionCronsCount: Int?
    var stopHookActive: Bool?

    enum CodingKeys: String, CodingKey {
        case event
        case state
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

    init() {}
    init(from decoder: Decoder) {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        event = Lenient.string(c, .event)
        state = Lenient.string(c, .state)
        sessionId = Lenient.string(c, .sessionId)
        agentId = Lenient.string(c, .agentId)
        toolName = Lenient.string(c, .toolName)
        cwd = Lenient.string(c, .cwd)
        sessionTitle = Lenient.string(c, .sessionTitle)
        transcriptPath = Lenient.string(c, .transcriptPath)
        contextUsage = (try? c?.decodeIfPresent(AgentContextUsage.self, forKey: .contextUsage)) ?? nil
        assistantLastOutput = Lenient.string(c, .assistantLastOutput)
        apiErrorType = Lenient.string(c, .apiErrorType)
        headless = Lenient.bool(c, .headless)
        trigger = Lenient.string(c, .trigger)
        source = Lenient.string(c, .source)
        backgroundTasksCount = Lenient.int(c, .backgroundTasksCount)
        sessionCronsCount = Lenient.int(c, .sessionCronsCount)
        stopHookActive = Lenient.bool(c, .stopHookActive)
    }
}

/// A tracked agent session.
struct AgentSession: Identifiable, Codable, Defaults.Serializable {
    let id: String          // session_id
    var agentId: String
    var state: AgentState
    var title: String
    var contextPercent: Double?
    var lastOutput: String?
    var cwd: String?
    var headless: Bool
    var updatedAt: Date
    var transcriptPath: String?  // ~/.claude/projects/.../<session>.jsonl — for deriving a title
    var contextUsed: Int?    // context-window tokens used (latest assistant turn)
    var contextLimit: Int?   // context-window size (e.g. 200000)
}

extension AgentSession {
    /// Remaining context as a percentage. Computed from the real token count, correcting for the
    /// 1M-context beta that the hook can't detect from the model name: if usage already exceeds
    /// the reported limit, the window is actually the 1M tier.
    var contextRemainingPercent: Int? {
        if let used = contextUsed, used > 0 {
            let reported = contextLimit ?? 200_000
            let limit = used > reported ? 1_000_000 : reported
            return max(0, min(100, Int((Double(limit - used) / Double(limit) * 100).rounded())))
        }
        if let p = contextPercent { return max(0, min(100, 100 - Int(p.rounded()))) }
        return nil
    }
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

    /// Bundled brand-icon filename (reused from clawd-on-desk's agent icons), if any.
    static func iconFileName(_ id: String) -> String? {
        switch id {
        case "claude-code": return "claude-code"
        case "codex": return "codex"
        case "cursor", "cursor-agent": return "cursor-agent"
        case "gemini", "gemini-cli": return "gemini-cli"
        case "qwen", "qwen-code": return "qwen-code"
        case "opencode": return "opencode"
        case "codebuddy": return "codebuddy"
        case "copilot", "copilot-cli": return "copilot-cli"
        case "kiro", "kiro-cli": return "kiro-cli"
        case "kimi", "kimi-cli": return "kimi-cli"
        case "codewhale": return "codewhale"
        case "qoder": return "qoder"
        case "reasonix": return "reasonix"
        case "pi": return "pi"
        case "openclaw": return "openclaw"
        case "hermes": return "hermes"
        case "antigravity", "antigravity-cli": return "antigravity-cli"
        default: return nil
        }
    }

    /// The real tool logo (bundled PNG), or nil to fall back to an SF Symbol.
    static func image(_ id: String) -> NSImage? {
        guard let name = iconFileName(id),
              let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
