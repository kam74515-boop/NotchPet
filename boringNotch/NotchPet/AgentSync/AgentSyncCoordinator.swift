//
//  AgentSyncCoordinator.swift
//  NotchPet — AI coding-agent task sync
//
//  Top-level owner: starts/stops the listener, installs hooks, writes the runtime
//  port file, and turns completion/error events into a system notification + a
//  closed-notch peek. Also drives the optional desktop pet.
//

import SwiftUI
import Defaults

extension Defaults.Keys {
    static let agentSyncEnabled = Key<Bool>("notchpet.agentsync.enabled", default: true)
    static let agentCompletionNotification = Key<Bool>("notchpet.agentsync.completionNotification", default: true)
    static let agentCompletionSound = Key<Bool>("notchpet.agentsync.completionSound", default: true)
    static let agentPermissionsEnabled = Key<Bool>("notchpet.agentsync.permissionsEnabled", default: false)
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
                let result = await HookInstaller.install(port: port, permissionsEnabled: Defaults[.agentPermissionsEnabled])
                self.lastInstallMessage = result.message
                self.hooksInstalled = await HookInstaller.isInstalled()
            }
        }
        if Defaults[.agentPermissionsEnabled] {
            listener.onPermission = { [weak self] payload, respond in
                Task { @MainActor in self?.presentPermission(payload, respond: respond) }
            }
        }
        listener.start()
        // The pet lives INSIDE the notch (see AgentLiveActivity / AgentPetView),
        // so there is no floating desktop window to show/hide here.
    }

    func stop() {
        running = false
        listener.stop()
    }

    func setEnabled(_ on: Bool) {
        Defaults[.agentSyncEnabled] = on
        if on { start() } else { stop() }
    }

    func reinstallHooks() {
        Task { @MainActor in
            let r = await HookInstaller.install(port: activePort ?? 23333, permissionsEnabled: Defaults[.agentPermissionsEnabled])
            lastInstallMessage = r.message
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
        PermissionBubbleController.shared.present(payload, respond: respond)
    }
}
