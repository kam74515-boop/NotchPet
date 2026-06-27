//
//  SystemActionsManager.swift
//  NotchPet
//
//  系统快捷指令 — a sandbox-safe grid of quick system actions. Everything here is
//  driven through NSWorkspace.open (URLs / app bundle URLs). We deliberately avoid
//  any path that needs Process/NSTask, AppleScript, or private SPIs, because the
//  app is sandboxed. See `omittedActions` (and the module notes) for the actions we
//  intentionally do NOT implement because the sandbox blocks them.
//

import AppKit
import SwiftUI
import Defaults

// MARK: - Action model

/// A single quick action. `perform` is a synchronous, side-effecting closure that
/// runs on the main actor (all our actions are NSWorkspace calls, which are cheap).
struct QuickAction: Identifiable {
    /// Stable id used both for SwiftUI diffing and for the persisted enable/order lists.
    let id: String
    let title: String
    /// SF Symbol name for the tile.
    let symbol: String
    /// Short helper text shown on hover.
    let help: String
    /// The work the tile performs. Returns false if the action could not be invoked
    /// (e.g. nothing on disk handled the URL), so the view can surface an error.
    let perform: @MainActor () -> Bool
}

// MARK: - Defaults keys

extension Defaults.Keys {
    /// Per-action enable map keyed by action id. Missing entry == enabled.
    static let quickActionsEnabled = Key<[String: Bool]>("notchpet.quickActions.enabled", default: [:])
    /// User-defined ordering of action ids (ids not present fall back to registry order).
    static let quickActionsOrder = Key<[String]>("notchpet.quickActions.order", default: [])
}

// MARK: - Manager

@MainActor
final class SystemActionsManager: ObservableObject {
    static let shared = SystemActionsManager()

    /// Transient, user-facing error (e.g. an action whose handler wasn't found).
    @Published var lastError: String?

    private init() {}

    // MARK: Registry

    /// Every available action, in default order. Each one is sandbox-safe.
    ///
    /// System Settings panes are opened via the `x-apple.systempreferences:` URL
    /// scheme; on modern macOS these resolve to the appropriate Settings.app pane.
    /// Built-in utilities (Mission Control, Launchpad, Screenshot) are opened by
    /// their bundle URL discovered through NSWorkspace / LaunchServices.
    let allActions: [QuickAction] = {
        var actions: [QuickAction] = []

        // ----- System Settings panes (URL scheme) -----
        func settingsPane(id: String, title: String, symbol: String, urls: [String]) -> QuickAction {
            QuickAction(id: id, title: title, symbol: symbol, help: "Open \(title) settings") {
                SystemActionsManager.openFirstAvailable(urls)
            }
        }

        actions.append(settingsPane(
            id: "displays", title: "Displays", symbol: "display",
            urls: [
                "x-apple.systempreferences:com.apple.Displays-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.displays",
            ]))
        actions.append(settingsPane(
            id: "sound", title: "Sound", symbol: "speaker.wave.2.fill",
            urls: [
                "x-apple.systempreferences:com.apple.Sound-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.sound",
            ]))
        actions.append(settingsPane(
            id: "bluetooth", title: "Bluetooth", symbol: "dot.radiowaves.right",
            urls: [
                "x-apple.systempreferences:com.apple.BluetoothSettings",
                "x-apple.systempreferences:com.apple.preferences.Bluetooth",
            ]))
        actions.append(settingsPane(
            id: "network", title: "Network", symbol: "network",
            urls: [
                "x-apple.systempreferences:com.apple.Network-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.network",
            ]))
        actions.append(settingsPane(
            id: "wifi", title: "Wi-Fi", symbol: "wifi",
            urls: [
                "x-apple.systempreferences:com.apple.wifi-settings-extension",
                "x-apple.systempreferences:com.apple.preference.network?Wi-Fi",
            ]))
        actions.append(settingsPane(
            id: "battery", title: "Battery", symbol: "battery.100",
            urls: [
                "x-apple.systempreferences:com.apple.Battery-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.battery",
            ]))
        actions.append(settingsPane(
            id: "notifications", title: "Notifications", symbol: "bell.badge.fill",
            urls: [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications",
            ]))
        // "Focus" pane is the supported, sandbox-safe way to reach Do Not Disturb.
        actions.append(settingsPane(
            id: "focus", title: "Focus", symbol: "moon.fill",
            urls: [
                "x-apple.systempreferences:com.apple.Focus-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications?Focus",
            ]))
        actions.append(settingsPane(
            id: "appearance", title: "Appearance", symbol: "circle.lefthalf.filled",
            urls: [
                "x-apple.systempreferences:com.apple.Appearance-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.general",
            ]))

        // ----- Built-in utilities (bundle URLs via NSWorkspace) -----
        actions.append(QuickAction(
            id: "missionControl", title: "Mission Control", symbol: "rectangle.3.group.fill",
            help: "Open Mission Control") {
                SystemActionsManager.openBundle(
                    identifiers: ["com.apple.exposelauncher"],
                    fallbackPaths: ["/System/Applications/Mission Control.app",
                                    "/Applications/Mission Control.app"])
            })
        actions.append(QuickAction(
            id: "launchpad", title: "Launchpad", symbol: "square.grid.3x3.fill",
            help: "Open Launchpad") {
                SystemActionsManager.openBundle(
                    identifiers: ["com.apple.launchpad.launcher"],
                    fallbackPaths: ["/System/Applications/Launchpad.app",
                                    "/Applications/Launchpad.app"])
            })
        actions.append(QuickAction(
            id: "screenshot", title: "Screenshot", symbol: "camera.viewfinder",
            help: "Open the Screenshot tool") {
                SystemActionsManager.openBundle(
                    identifiers: ["com.apple.screenshot.launcher"],
                    fallbackPaths: ["/System/Applications/Utilities/Screenshot.app",
                                    "/Applications/Utilities/Screenshot.app"])
            })

        return actions
    }()

    /// Quick lookup by id.
    private lazy var actionsByID: [String: QuickAction] = {
        Dictionary(uniqueKeysWithValues: allActions.map { ($0.id, $0) })
    }()

    // MARK: Enable / order queries

    func isEnabled(_ action: QuickAction) -> Bool {
        Defaults[.quickActionsEnabled][action.id] ?? true
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        var map = Defaults[.quickActionsEnabled]
        map[id] = enabled
        Defaults[.quickActionsEnabled] = map
        objectWillChange.send()
    }

    /// All actions in the user-defined order (registry order as fallback for new ids).
    var orderedActions: [QuickAction] {
        let order = Defaults[.quickActionsOrder]
        guard !order.isEmpty else { return allActions }
        return allActions.sorted { a, b in
            (order.firstIndex(of: a.id) ?? Int.max) < (order.firstIndex(of: b.id) ?? Int.max)
        }
    }

    /// Enabled actions in user order — what the grid renders.
    var visibleActions: [QuickAction] {
        orderedActions.filter { isEnabled($0) }
    }

    /// Reorder within the *full* ordered list (used by the settings list).
    func move(from source: IndexSet, to destination: Int) {
        var ids = orderedActions.map { $0.id }
        ids.move(fromOffsets: source, toOffset: destination)
        Defaults[.quickActionsOrder] = ids
        objectWillChange.send()
    }

    // MARK: Execution

    /// Run an action by id, surfacing an error if it couldn't be invoked.
    func run(_ action: QuickAction) {
        let ok = action.perform()
        if !ok {
            lastError = "Couldn’t open “\(action.title)”."
        } else {
            lastError = nil
        }
    }

    // MARK: - Sandbox-safe primitives

    /// Try each URL string in turn, opening the first one NSWorkspace accepts.
    /// Returns true if any opened.
    static func openFirstAvailable(_ strings: [String]) -> Bool {
        for string in strings {
            guard let url = URL(string: string) else { continue }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }
        return false
    }

    /// Resolve an app by bundle identifier (preferred) or a set of fallback paths,
    /// then launch it. Returns true on success.
    static func openBundle(identifiers: [String], fallbackPaths: [String]) -> Bool {
        // Prefer LaunchServices lookup by bundle id (robust across macOS layouts).
        for identifier in identifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                if openApplication(at: url) { return true }
            }
        }
        // Fall back to known on-disk locations.
        for path in fallbackPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                if openApplication(at: url) { return true }
            }
        }
        return false
    }

    /// Launch an app bundle. We use the async API but report best-effort success
    /// synchronously (a reachable bundle URL essentially always launches).
    @discardableResult
    private static func openApplication(at url: URL) -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        return true
    }
}

// MARK: - Intentionally omitted (sandbox-blocked)

extension SystemActionsManager {
    /// Documentation of actions we deliberately do NOT implement because the App
    /// Sandbox blocks them. Surfaced nowhere in the UI; kept for maintainers.
    ///
    /// - Lock Screen: needs the private `SACLockScreenImmediate()` SPI or an
    ///   AppleScript bridge — both unavailable / disallowed under sandbox.
    /// - Sleep Displays / Sleep Mac: requires `pmset` (Process) or IOKit power SPIs.
    /// - Start Screen Saver: launching ScreenSaverEngine is restricted under sandbox.
    /// - Empty Trash: the only reliable routes are Finder AppleScript or direct
    ///   filesystem deletion of ~/.Trash, neither of which is sandbox-permitted.
    /// - Toggle Wi-Fi / Bluetooth radios: needs CoreWLAN / IOBluetooth privileged
    ///   APIs; we open the relevant *settings pane* instead.
    /// - Toggle Do Not Disturb directly: no public, sandbox-safe API; we open the
    ///   Focus settings pane instead.
    static let omittedActions: [String] = [
        "Lock Screen", "Sleep Displays", "Sleep Mac", "Start Screen Saver",
        "Empty Trash", "Toggle Wi-Fi radio", "Toggle Bluetooth radio",
        "Toggle Do Not Disturb directly",
    ]
}
