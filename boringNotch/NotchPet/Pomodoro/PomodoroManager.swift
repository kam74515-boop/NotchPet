//
//  PomodoroManager.swift
//  NotchPet
//
//  Singleton state machine driving the Pomodoro (番茄钟) timer.
//
//  Design notes:
//  - The source of truth for an active phase is an *absolute* `phaseEndDate`.
//    Remaining time is always computed from Date() so the timer survives sleep,
//    app suspension and clock drift. We never decrement a counter per tick.
//  - A 1Hz Timer republishes `now` purely so SwiftUI views relying on @ObservedObject
//    redraw; views may also use their own TimelineView. The timer also detects
//    phase completion (including the case where the machine was asleep past the
//    end date) and advances the state machine.
//  - All mutable state lives on the main actor.
//

import Foundation
import Combine
import SwiftUI
import Defaults

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    // MARK: Published state

    /// Current phase of the state machine.
    @Published private(set) var phase: PomodoroPhase = .idle
    /// True while a phase is actively counting down (not paused, not idle).
    @Published private(set) var isRunning: Bool = false
    /// Absolute moment the current phase finishes. `nil` when idle.
    @Published private(set) var phaseEndDate: Date?
    /// Number of completed focus (work) sessions in the *current* cycle
    /// (resets after a long break). Drives the cycle dots.
    @Published private(set) var cyclePosition: Int = 0
    /// A monotonically-updated clock used to trigger view refreshes each second.
    @Published private(set) var now: Date = Date()

    // MARK: Persisted state

    /// Lifetime + daily stats.
    @Published var stats: PomodoroStats {
        didSet { Defaults[.pomodoroStats] = stats }
    }

    // MARK: Private

    /// Remaining seconds captured when the user pauses; restored on resume.
    private var pausedRemaining: TimeInterval?
    private var ticker: Timer?

    private init() {
        var s = Defaults[.pomodoroStats]
        s.rollDayIfNeeded()
        stats = s
        Defaults[.pomodoroStats] = s
    }

    // MARK: Derived values

    /// Total configured length of the given phase in seconds.
    func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .idle:       return 0
        case .work:       return TimeInterval(max(1, Defaults[.pomodoroWorkMinutes]) * 60)
        case .shortBreak: return TimeInterval(max(1, Defaults[.pomodoroShortBreakMinutes]) * 60)
        case .longBreak:  return TimeInterval(max(1, Defaults[.pomodoroLongBreakMinutes]) * 60)
        }
    }

    /// Seconds remaining in the current phase, clamped to >= 0.
    var remaining: TimeInterval {
        if let paused = pausedRemaining { return max(0, paused) }
        guard let end = phaseEndDate else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    /// Fractional progress through the current phase, 0...1.
    var progress: Double {
        let total = duration(for: phase)
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / total))
    }

    /// MM:SS string for the remaining time (or full duration when idle).
    var remainingString: String {
        let secs = Int((phase == .idle ? duration(for: .work) : remaining).rounded())
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    /// Whether a session is paused (active phase but not running).
    var isPaused: Bool { phase != .idle && !isRunning && pausedRemaining != nil }

    // MARK: Controls

    /// Begin a fresh session at the work phase from idle/stopped.
    func start() {
        NotificationManager.shared.requestAuthorizationIfNeeded()
        cyclePosition = 0
        begin(phase: .work)
    }

    /// Pause the active countdown, freezing the remaining time.
    func pause() {
        guard isRunning, let end = phaseEndDate else { return }
        pausedRemaining = max(0, end.timeIntervalSince(Date()))
        isRunning = false
        phaseEndDate = nil
        stopTicker()
        objectWillChange.send()
    }

    /// Resume a paused countdown using the frozen remaining time.
    func resume() {
        guard !isRunning, phase != .idle, let rem = pausedRemaining else { return }
        phaseEndDate = Date().addingTimeInterval(rem)
        pausedRemaining = nil
        isRunning = true
        startTicker()
        objectWillChange.send()
    }

    /// Convenience toggle used by the primary play/pause button.
    func toggle() {
        switch phase {
        case .idle:
            start()
        default:
            if isRunning { pause() } else { resume() }
        }
    }

    /// Skip to the next phase immediately *without* recording a completion.
    func skip() {
        guard phase != .idle else { return }
        advance(completed: false)
    }

    /// Stop everything and return to idle. Does not touch lifetime stats.
    func reset() {
        stopTicker()
        phase = .idle
        isRunning = false
        phaseEndDate = nil
        pausedRemaining = nil
        cyclePosition = 0
        cancelPendingNotification()
        objectWillChange.send()
    }

    // MARK: State machine

    /// Enter `phase`, arming an absolute end date and (if running) the ticker.
    private func begin(phase newPhase: PomodoroPhase, autoRun: Bool = true) {
        cancelPendingNotification()
        phase = newPhase
        pausedRemaining = nil
        now = Date()

        guard newPhase != .idle else {
            isRunning = false
            phaseEndDate = nil
            return
        }

        let total = duration(for: newPhase)
        phaseEndDate = Date().addingTimeInterval(total)
        isRunning = autoRun

        if autoRun {
            startTicker()
            scheduleEndNotification(for: newPhase, after: total)
        }
        objectWillChange.send()
    }

    /// Determine and transition to the phase that follows the current one.
    /// `completed` indicates whether the just-finished phase ran to completion
    /// (only then do we record stats / advance the cycle counter).
    private func advance(completed: Bool) {
        let finished = phase
        let interval = max(1, Defaults[.pomodoroLongBreakInterval])
        let autoStart = Defaults[.pomodoroAutoStart]

        if finished == .work {
            if completed {
                stats.recordFocusCompletion(minutes: Defaults[.pomodoroWorkMinutes])
                cyclePosition += 1
            }
            // Long break after every `interval` completed focus sessions.
            let next: PomodoroPhase = (cyclePosition % interval == 0 && cyclePosition > 0)
                ? .longBreak : .shortBreak
            begin(phase: next, autoRun: autoStart)
        } else if finished.isBreak {
            if finished == .longBreak { cyclePosition = 0 }
            begin(phase: .work, autoRun: autoStart)
        }
    }

    // MARK: Ticker

    private func startTicker() {
        stopTicker()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Common run-loop mode so it keeps firing during menu/notch interaction.
        RunLoop.main.add(t, forMode: .common)
        ticker = t
        tick() // immediate refresh
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Per-second update: refresh `now` and detect (possibly overslept) completion.
    private func tick() {
        now = Date()
        guard isRunning, let end = phaseEndDate else { return }
        if now >= end {
            // Phase ran to completion (in-app banner is delivered by the
            // pre-scheduled notification; if we were asleep past the end the OS
            // already fired it). Advance the machine.
            advance(completed: true)
        }
    }

    // MARK: Notifications

    private var pendingNotificationID: String?

    private func scheduleEndNotification(for phase: PomodoroPhase, after delay: TimeInterval) {
        let id = "notchpet.pomodoro.phase-end"
        pendingNotificationID = id
        let sound = Defaults[.pomodoroPlaySound]
        let (title, body): (String, String)
        switch phase {
        case .work:
            title = "Focus complete"
            body  = "Nice work. Time for a break."
        case .shortBreak:
            title = "Break over"
            body  = "Back to focus."
        case .longBreak:
            title = "Long break over"
            body  = "Ready for the next round?"
        case .idle:
            return
        }
        NotificationManager.shared.schedule(id: id, title: title, body: body,
                                            after: delay, sound: sound)
    }

    private func cancelPendingNotification() {
        if let id = pendingNotificationID {
            NotificationManager.shared.cancel(id: id)
            pendingNotificationID = nil
        }
    }
}

// MARK: - Defaults keys

extension Defaults.Keys {
    static let pomodoroWorkMinutes        = Key<Int>("notchpet.pomodoro.workMinutes", default: 25)
    static let pomodoroShortBreakMinutes  = Key<Int>("notchpet.pomodoro.shortBreakMinutes", default: 5)
    static let pomodoroLongBreakMinutes   = Key<Int>("notchpet.pomodoro.longBreakMinutes", default: 15)
    /// Number of focus sessions before a long break.
    static let pomodoroLongBreakInterval  = Key<Int>("notchpet.pomodoro.longBreakInterval", default: 4)
    /// Automatically start the next phase when one ends.
    static let pomodoroAutoStart          = Key<Bool>("notchpet.pomodoro.autoStart", default: true)
    /// Play a sound with the phase-end notification.
    static let pomodoroPlaySound          = Key<Bool>("notchpet.pomodoro.playSound", default: true)
    /// Show the compact live activity in the closed notch while running.
    static let pomodoroShowInClosedNotch  = Key<Bool>("notchpet.pomodoro.showInClosedNotch", default: true)
    /// Persisted lifetime + daily statistics.
    static let pomodoroStats              = Key<PomodoroStats>("notchpet.pomodoro.stats", default: PomodoroStats())
}
