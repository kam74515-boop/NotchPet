//
//  HookInstaller.swift
//  NotchPet — AI coding-agent task sync
//
//  Idempotently merges NotchPet's hook entries into ~/.claude/settings.json (via the
//  non-sandboxed XPC helper, since the sandboxed app can't reach the real home dir).
//  The installed hook is a tiny dumb-pipe shell script that forwards each Claude Code
//  hook event to the local AgentHTTPListener — all parsing happens app-side.
//

import Foundation

/// Returns the user's REAL home directory even from inside the App Sandbox
/// (NSHomeDirectory() would return the container path).
func notchPetRealHome() -> String {
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
        return String(cString: dir)
    }
    return NSHomeDirectory()
}

struct HookInstallResult {
    var ok: Bool
    var added: Int
    var message: String
}

enum HookInstaller {
    static let marker = "notchpet-hook.sh"
    static let legacyMarkers = ["notch-agent-hook.sh"]

    static var home: String { notchPetRealHome() }
    static var claudeSettingsPath: String { home + "/.claude/settings.json" }
    // NotchPet uses its OWN dir + port range so it never collides with a real
    // Clawd on Desk install (which owns ~/.clawd/runtime.json and ports 23333–23337).
    static var hookScriptPath: String { home + "/.notchpet/notchpet-hook.sh" }
    static var runtimeConfigPath: String { home + "/.notchpet/runtime.json" }

    /// Command-hook lifecycle events (dumb pipe: event name passed as argv[1]).
    static let commandEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "Stop", "StopFailure", "SubagentStart", "SubagentStop",
        "Notification", "Elicitation", "PreCompact", "PostCompact",
    ]

    static let hookScript = """
    #!/bin/sh
    # NotchPet agent hook — forwards Claude Code hook events to the local NotchPet listener.
    # argv[1] = EventName; stdin = the hook JSON payload. Fire-and-forget (never blocks the agent).
    PORT=$(plutil -extract port raw "$HOME/.notchpet/runtime.json" 2>/dev/null || echo 24333)
    exec curl -s -m 2 -X POST "http://127.0.0.1:$PORT/state?event=$1" \\
      -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1
    """

    /// Write the runtime port file (so the hook script can find the listener).
    static func writeRuntime(port: UInt16) async {
        let json: [String: Any] = ["app": "notchpet", "port": Int(port)]
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            await XPCHelperClient.shared.writeUserFile(runtimeConfigPath, data: data)
        }
    }

    /// Install (idempotent) the hook script + settings.json entries.
    static func install(port: UInt16, permissionsEnabled: Bool) async -> HookInstallResult {
        // 1) Write/refresh the hook script (executable).
        let scriptOK = await XPCHelperClient.shared.writeUserFile(
            hookScriptPath, data: Data(hookScript.utf8), executable: true)
        guard scriptOK else {
            return HookInstallResult(ok: false, added: 0, message: "Could not write hook script (helper unavailable).")
        }

        // 2) Read existing settings.json (preserve all user keys).
        let existing = await XPCHelperClient.shared.readUserFile(claudeSettingsPath, maxBytes: 0)
        let root: NSMutableDictionary
        if let existing,
           let obj = try? JSONSerialization.jsonObject(with: existing, options: [.mutableContainers, .mutableLeaves]) as? NSMutableDictionary {
            root = obj
        } else {
            root = NSMutableDictionary()
        }

        let hooks: NSMutableDictionary
        if let h = root["hooks"] as? NSMutableDictionary {
            hooks = h
        } else {
            hooks = NSMutableDictionary()
            root["hooks"] = hooks
        }

        var added = 0
        for event in commandEvents {
            let groups: NSMutableArray
            if let g = hooks[event] as? NSMutableArray {
                groups = g
            } else {
                groups = NSMutableArray()
                hooks[event] = groups
            }
            // Remove any prior NotchPet entry (incl. legacy ~/.clawd path) so we never
            // duplicate or leave a stale wrong-path hook, then add a fresh one. This does
            // NOT touch a real Clawd on Desk install's clawd-hook.js entries.
            stripOurHooks(from: groups)
            groups.add(commandGroup(for: event))
            added += 1
        }

        // 3) Permission HTTP hook (only when bubbles are enabled).
        if permissionsEnabled {
            let groups: NSMutableArray
            if let g = hooks["PermissionRequest"] as? NSMutableArray {
                groups = g
            } else {
                groups = NSMutableArray()
                hooks["PermissionRequest"] = groups
            }
            if !groupsContainPermissionHook(groups) {
                groups.add(permissionGroup(port: port))
                added += 1
            }
        }

        // 4) Atomic write back via helper.
        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else {
            return HookInstallResult(ok: false, added: 0, message: "Could not serialize settings.")
        }
        let wrote = await XPCHelperClient.shared.writeUserFile(claudeSettingsPath, data: out)
        return HookInstallResult(ok: wrote, added: added,
                                 message: wrote ? "Installed (\(added) new hook entries)." : "Could not write settings.json.")
    }

    /// Remove NotchPet's hook entries (keeps the user's own hooks intact).
    static func uninstall() async -> HookInstallResult {
        guard let existing = await XPCHelperClient.shared.readUserFile(claudeSettingsPath, maxBytes: 0),
              let root = try? JSONSerialization.jsonObject(with: existing, options: [.mutableContainers, .mutableLeaves]) as? NSMutableDictionary,
              let hooks = root["hooks"] as? NSMutableDictionary else {
            return HookInstallResult(ok: true, added: 0, message: "Nothing to remove.")
        }
        for (_, value) in hooks {
            guard let groups = value as? NSMutableArray else { continue }
            let survivors = groups.compactMap { $0 as? NSDictionary }.filter { !groupDictContainsOurHook($0) }
            groups.removeAllObjects()
            groups.addObjects(from: survivors)
        }
        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted]) else {
            return HookInstallResult(ok: false, added: 0, message: "Could not serialize settings.")
        }
        let wrote = await XPCHelperClient.shared.writeUserFile(claudeSettingsPath, data: out)
        return HookInstallResult(ok: wrote, added: 0, message: wrote ? "Removed NotchPet hooks." : "Could not write settings.json.")
    }

    /// Whether NotchPet's hooks are currently present.
    static func isInstalled() async -> Bool {
        guard let existing = await XPCHelperClient.shared.readUserFile(claudeSettingsPath, maxBytes: 0),
              let text = String(data: existing, encoding: .utf8) else { return false }
        return text.contains(marker)
    }

    // MARK: - Builders

    private static func commandGroup(for event: String) -> [String: Any] {
        [
            "matcher": "",
            "hooks": [
                // async:true → fire-and-forget, never blocks the agent's tool calls.
                ["type": "command", "command": "\(hookScriptPath) \(event)", "timeout": 5, "async": true],
            ],
        ]
    }

    private static func permissionGroup(port: UInt16) -> [String: Any] {
        [
            "matcher": "",
            "hooks": [
                ["type": "http", "url": "http://127.0.0.1:\(port)/permission", "timeout": 600],
            ],
        ]
    }

    private static func stripOurHooks(from groups: NSMutableArray) {
        let survivors = groups.compactMap { $0 as? NSDictionary }.filter { !groupDictContainsOurHook($0) }
        groups.removeAllObjects()
        groups.addObjects(from: survivors)
    }

    private static func groupsContainPermissionHook(_ groups: NSMutableArray) -> Bool {
        groups.compactMap { $0 as? NSDictionary }.contains { dict in
            guard let inner = dict["hooks"] as? [[String: Any]] else { return false }
            return inner.contains { ($0["url"] as? String)?.contains("/permission") == true }
        }
    }

    private static func groupDictContainsOurHook(_ dict: NSDictionary) -> Bool {
        guard let inner = dict["hooks"] as? [[String: Any]] else { return false }
        let allMarkers = [marker] + legacyMarkers
        return inner.contains { hook in
            guard let cmd = hook["command"] as? String else { return false }
            return allMarkers.contains { cmd.contains($0) }
        }
    }
}
