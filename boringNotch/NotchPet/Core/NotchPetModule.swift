//
//  NotchPetModule.swift
//  NotchPet
//
//  Registry of optional NotchPet feature tabs. Drives the tab bar (TabSelectionView)
//  and the "customizable display icons" feature (enable/disable + reorder).
//

import SwiftUI
import Defaults

/// Describes a NotchPet feature module that can appear as a tab in the expanded notch.
struct NotchPetModule: Identifiable {
    let id: String          // stable key (also used as a Defaults sub-key)
    let label: String
    let icon: String        // SF Symbol name
    let view: NotchViews
    let defaultEnabled: Bool
}

enum NotchPetModuleRegistry {
    /// All optional feature tabs. The built-in Home/Shelf tabs are handled separately
    /// in TabSelectionView so they keep their existing behavior.
    static let all: [NotchPetModule] = [
        // clawd-on-desk AI agent page first so it's always visible in the tab bar.
        NotchPetModule(id: "agents", label: "Agents", icon: "cpu", view: .agents, defaultEnabled: true),
        // App launcher next so the "apps" page is reachable without scrolling.
        NotchPetModule(id: "launcher", label: "Launcher", icon: "square.grid.2x2.fill", view: .launcher, defaultEnabled: true),
        NotchPetModule(id: "pomodoro", label: "Pomodoro", icon: "timer", view: .pomodoro, defaultEnabled: true),
        NotchPetModule(id: "todo", label: "To-Do", icon: "checklist", view: .todo, defaultEnabled: true),
        NotchPetModule(id: "notes", label: "Notes", icon: "note.text", view: .notes, defaultEnabled: true),
        NotchPetModule(id: "weather", label: "Weather", icon: "cloud.sun.fill", view: .weather, defaultEnabled: true),
        NotchPetModule(id: "lyrics", label: "Lyrics", icon: "music.note.list", view: .lyrics, defaultEnabled: true),
        NotchPetModule(id: "photos", label: "Photos", icon: "photo.on.rectangle", view: .photos, defaultEnabled: true),
        NotchPetModule(id: "quickActions", label: "Actions", icon: "bolt.fill", view: .quickActions, defaultEnabled: true),
    ]

    static func module(for view: NotchViews) -> NotchPetModule? {
        all.first { $0.view == view }
    }

    static func isEnabled(_ m: NotchPetModule) -> Bool {
        Defaults[.enabledModules][m.id] ?? m.defaultEnabled
    }

    /// Enabled feature modules in the user-defined order (registry order as fallback).
    static var enabledOrdered: [NotchPetModule] {
        let order = Defaults[.moduleOrder]
        let enabled = all.filter { isEnabled($0) }
        guard !order.isEmpty else { return enabled }
        return enabled.sorted { a, b in
            (order.firstIndex(of: a.id) ?? Int.max) < (order.firstIndex(of: b.id) ?? Int.max)
        }
    }
}

extension Defaults.Keys {
    /// Per-module enable toggles keyed by module id. A missing entry means "use defaultEnabled".
    static let enabledModules = Key<[String: Bool]>("notchpet.enabledModules", default: [:])
    /// Ordering of feature tabs by module id (ids not present fall back to registry order).
    static let moduleOrder = Key<[String]>("notchpet.moduleOrder", default: [])
}
