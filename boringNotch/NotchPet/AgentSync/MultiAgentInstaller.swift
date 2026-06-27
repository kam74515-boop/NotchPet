//
//  MultiAgentInstaller.swift
//  NotchPet — AI coding-agent task sync
//
//  Supports ALL the coding tools/IDEs that clawd-on-desk supports, by reusing its
//  ready-made per-agent installer scripts (vendored as clawd-hooks.tgz with the server
//  port/runtime/id rewritten to NotchPet). The non-sandboxed XPC helper extracts the
//  bundle into ~/.notchpet/clawd and runs `node <agent>-install.js` for each enabled tool.
//  Those installers write a hook into each tool's own config that POSTs events to
//  NotchPet's listener (127.0.0.1:24333). Claude Code keeps using HookInstaller.
//

import Foundation
import Defaults

struct CodingAgentDef: Identifiable {
    let id: String          // agent id (matches AgentKind + event agent_id)
    let installer: String   // clawd installer script filename
    let defaultEnabled: Bool
}

extension Defaults.Keys {
    static let enabledCodingAgents = Key<[String: Bool]>("notchpet.agentsync.enabledAgents", default: [:])
    static let multiAgentHooksMaterialized = Key<Bool>("notchpet.agentsync.hooksMaterialized", default: false)
}

enum MultiAgentInstaller {
    /// Every coding tool clawd-on-desk ships an installer for (Claude Code excluded —
    /// it's handled by HookInstaller's own forwarder).
    static let agents: [CodingAgentDef] = [
        // Claude Code uses clawd's rich installer too, so we get the real conversation
        // title (computed from the transcript) and consistent session ids.
        CodingAgentDef(id: "claude-code", installer: "install.js", defaultEnabled: true),
        CodingAgentDef(id: "codex", installer: "codex-install.js", defaultEnabled: true),
        CodingAgentDef(id: "cursor", installer: "cursor-install.js", defaultEnabled: true),
        CodingAgentDef(id: "gemini", installer: "gemini-install.js", defaultEnabled: true),
        CodingAgentDef(id: "antigravity", installer: "antigravity-install.js", defaultEnabled: true),
        CodingAgentDef(id: "qwen", installer: "qwen-code-install.js", defaultEnabled: true),
        CodingAgentDef(id: "opencode", installer: "opencode-install.js", defaultEnabled: true),
        CodingAgentDef(id: "codebuddy", installer: "codebuddy-install.js", defaultEnabled: true),
        CodingAgentDef(id: "copilot", installer: "copilot-install.js", defaultEnabled: true),
        CodingAgentDef(id: "kiro", installer: "kiro-install.js", defaultEnabled: true),
        CodingAgentDef(id: "kimi", installer: "kimi-install.js", defaultEnabled: true),
        CodingAgentDef(id: "codewhale", installer: "codewhale-install.js", defaultEnabled: true),
        CodingAgentDef(id: "qoder", installer: "qoder-install.js", defaultEnabled: true),
        CodingAgentDef(id: "reasonix", installer: "reasonix-install.js", defaultEnabled: true),
        CodingAgentDef(id: "pi", installer: "pi-install.js", defaultEnabled: true),
        CodingAgentDef(id: "openclaw", installer: "openclaw-install.js", defaultEnabled: true),
        CodingAgentDef(id: "hermes", installer: "hermes-install.js", defaultEnabled: true),
    ]

    static var home: String { notchPetRealHome() }
    static var clawdDir: String { home + "/.notchpet/clawd" }
    static var archiveDest: String { home + "/.notchpet/clawd-hooks.tgz" }

    static func isEnabled(_ a: CodingAgentDef) -> Bool {
        Defaults[.enabledCodingAgents][a.id] ?? a.defaultEnabled
    }

    /// Copy the bundled hook bundle into ~/.notchpet and extract it (idempotent).
    @discardableResult
    static func materialize() async -> Bool {
        guard let url = Bundle.main.url(forResource: "clawd-hooks", withExtension: "tgz"),
              let data = try? Data(contentsOf: url) else {
            NSLog("NotchPet: clawd-hooks.tgz missing from bundle")
            return false
        }
        guard await XPCHelperClient.shared.writeUserFile(archiveDest, data: data) else { return false }
        return await XPCHelperClient.shared.extractNotchpetArchive(archiveDest, toDir: clawdDir)
    }

    /// Install hooks for all enabled tools. Runs clawd's idempotent installers, which
    /// preserve the user's existing config.
    static func installEnabled() async {
        guard await materialize() else { return }
        // Remove the old dumb Claude forwarder (notchpet-hook.sh) so Claude only uses
        // clawd's rich hook (real titles), avoiding double-posting.
        _ = await HookInstaller.uninstall()
        for a in agents where isEnabled(a) {
            let script = clawdDir + "/hooks/" + a.installer
            let (code, out) = await XPCHelperClient.shared.runNotchpetNode(script, args: [])
            NSLog("NotchPet install \(a.id): exit \(code) — \(out.prefix(160))")
        }
        Defaults[.multiAgentHooksMaterialized] = true
    }

    static func installIfNeeded() async {
        if !Defaults[.multiAgentHooksMaterialized] { await installEnabled() }
    }

    @discardableResult
    static func install(_ a: CodingAgentDef) async -> (Int32, String) {
        _ = await materialize()
        return await XPCHelperClient.shared.runNotchpetNode(clawdDir + "/hooks/" + a.installer, args: [])
    }

    @discardableResult
    static func uninstall(_ a: CodingAgentDef) async -> (Int32, String) {
        // Not all installers support --uninstall; failures are harmless.
        return await XPCHelperClient.shared.runNotchpetNode(clawdDir + "/hooks/" + a.installer, args: ["--uninstall"])
    }
}
