//
//  PomodoroModels.swift
//  NotchPet
//
//  Core value types for the Pomodoro (番茄钟) module: the phase state machine
//  and the persisted lifetime statistics. Kept dependency-light so the manager,
//  the expanded tab and the closed-notch live activity can all share them.
//

import SwiftUI
import Defaults

/// The four states of a Pomodoro session. `idle` means no session is active.
enum PomodoroPhase: String, Codable, CaseIterable, Defaults.Serializable {
    case idle
    case work
    case shortBreak
    case longBreak

    /// Human-readable label shown under the timer.
    var displayName: String {
        switch self {
        case .idle:       return "Ready"
        case .work:       return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak:  return "Long Break"
        }
    }

    /// SF Symbol representing the phase.
    var symbol: String {
        switch self {
        case .idle:       return "timer"
        case .work:       return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer.fill"
        case .longBreak:  return "figure.walk"
        }
    }

    /// Accent tint used for the ring and labels.
    var tint: Color {
        switch self {
        case .idle:       return .gray
        case .work:       return Color(red: 0.96, green: 0.30, blue: 0.30)   // tomato red
        case .shortBreak: return Color(red: 0.30, green: 0.78, blue: 0.55)   // mint green
        case .longBreak:  return Color(red: 0.33, green: 0.62, blue: 0.96)   // calm blue
        }
    }

    /// Whether this phase is a break (used for auto-start branching / styling).
    var isBreak: Bool { self == .shortBreak || self == .longBreak }

    /// Fallback default minutes (used only if Defaults somehow unavailable).
    var defaultMinutes: Int {
        switch self {
        case .idle:       return 0
        case .work:       return 25
        case .shortBreak: return 5
        case .longBreak:  return 15
        }
    }
}

/// Lifetime + per-day Pomodoro statistics, persisted via Defaults.
struct PomodoroStats: Codable, Equatable, Defaults.Serializable {
    /// Total completed focus sessions ever.
    var totalCompleted: Int = 0
    /// Total focused minutes ever (sum of completed work durations).
    var totalFocusMinutes: Int = 0
    /// Completed focus sessions for `lastDayKey` only.
    var completedToday: Int = 0
    /// `yyyy-MM-dd` key for the day `completedToday` belongs to.
    var lastDayKey: String = ""

    /// Today's day key in the user's calendar/timezone.
    static func dayKey(for date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Roll the daily counter over if the stored day no longer matches today.
    mutating func rollDayIfNeeded(now: Date = Date()) {
        let key = PomodoroStats.dayKey(for: now)
        if lastDayKey != key {
            lastDayKey = key
            completedToday = 0
        }
    }

    /// Record one completed focus session of `minutes` length.
    mutating func recordFocusCompletion(minutes: Int, now: Date = Date()) {
        rollDayIfNeeded(now: now)
        totalCompleted += 1
        completedToday += 1
        totalFocusMinutes += max(0, minutes)
    }
}
