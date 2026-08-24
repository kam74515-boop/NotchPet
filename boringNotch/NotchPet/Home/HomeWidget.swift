//
//  HomeWidget.swift
//  NotchPet
//
//  Registry for the Nook-X-style customizable Home widget board. Drives which compact
//  widget cards appear on the Home page and in what order (enable/disable + reorder),
//  mirroring the tab-customization pattern in NotchPetModule.
//

import SwiftUI
import Defaults

/// A compact widget that can appear on the Home board.
enum HomeWidgetKind: String, CaseIterable, Identifiable {
    case clock
    case weather
    case music
    case calendar
    case todo
    case pomodoro
    case battery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .clock:    return "Clock"
        case .weather:  return "Weather"
        case .music:    return "Music"
        case .calendar: return "Calendar"
        case .todo:     return "To-Do"
        case .pomodoro: return "Pomodoro"
        case .battery:  return "Battery"
        }
    }

    var icon: String {
        switch self {
        case .clock:    return "clock"
        case .weather:  return "cloud.sun.fill"
        case .music:    return "music.note"
        case .calendar: return "calendar"
        case .todo:     return "checklist"
        case .pomodoro: return "timer"
        case .battery:  return "battery.100"
        }
    }

    var defaultEnabled: Bool {
        switch self {
        case .clock, .weather, .music, .todo: return true
        default:                              return false
        }
    }

    /// Relative width weight on the Home board. The enabled widgets share the panel width
    /// proportionally (no horizontal scrolling) — wider widgets (music/calendar) get more.
    var flex: CGFloat {
        switch self {
        case .clock:    return 1.1
        case .weather:  return 1.1
        case .music:    return 2.0
        case .calendar: return 2.0
        case .todo:     return 1.7
        case .pomodoro: return 1.3
        case .battery:  return 0.9
        }
    }
}

extension Defaults.Keys {
    /// Per-widget enable toggles keyed by widget id. Missing entry means "use defaultEnabled".
    static let homeWidgetsEnabled = Key<[String: Bool]>("notchpet.homeWidgets.enabled", default: [:])
    /// Ordering of Home widgets by id (ids not present fall back to declaration order).
    static let homeWidgetsOrder = Key<[String]>("notchpet.homeWidgets.order", default: [])
}

enum HomeWidgetRegistry {
    static let all: [HomeWidgetKind] = HomeWidgetKind.allCases

    static func isEnabled(_ w: HomeWidgetKind) -> Bool {
        Defaults[.homeWidgetsEnabled][w.id] ?? w.defaultEnabled
    }

    /// All widgets in the user's chosen order (declaration order as fallback) — for settings.
    static var allOrdered: [HomeWidgetKind] {
        let order = Defaults[.homeWidgetsOrder]
        guard !order.isEmpty else { return all }
        return all.sorted {
            (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
        }
    }

    /// Enabled widgets in the user's chosen order — for the Home board.
    static var enabledOrdered: [HomeWidgetKind] {
        allOrdered.filter { isEnabled($0) }
    }
}
