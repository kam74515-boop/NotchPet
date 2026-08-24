//
//  HealthReminderManager.swift
//  NotchPet
//
//  健康提醒 — water / posture (sedentary) / sleep reminders.
//
//  Design notes:
//  - Water & Posture are *interval* reminders that should only fire inside an
//    "active hours" window (e.g. 09:00–18:00). UNUserNotificationCenter's repeating
//    interval trigger cannot be constrained to a time window, so we drive these with
//    a chain of one-shot notifications computed from ABSOLUTE fire dates. After each
//    boundary we re-arm the next batch. This survives sleep (we always recompute from
//    Date(), never decrement a counter) and we keep a healthy buffer of pending fires
//    so the chain keeps going even if the app is closed for a while.
//  - Sleep is a fixed time-of-day reminder backed by a repeating calendar trigger.
//  - All scheduling goes through NotificationManager.shared. Ids are stable so we can
//    cancel/replace cleanly. Interval reminders use indexed ids (e.g.
//    "notchpet.reminder.water.3") because the system needs distinct ids per one-shot.
//

import Foundation
import Combine
import Defaults

// MARK: - Reminder kinds

enum HealthReminderKind: String, CaseIterable, Identifiable {
    case water
    case posture
    case sleep

    var id: String { rawValue }

    /// Stable id prefix used for scheduled notifications.
    var notificationIDPrefix: String { "notchpet.reminder.\(rawValue)" }

    var title: String {
        switch self {
        case .water:   return String(localized: "Time to drink water")
        case .posture: return String(localized: "Time to move")
        case .sleep:   return String(localized: "Bedtime reminder")
        }
    }

    var body: String {
        switch self {
        case .water:   return String(localized: "Get up and drink some water to stay hydrated 💧")
        case .posture: return String(localized: "You've been sitting a while — stand up and move around 🧍")
        case .sleep:   return String(localized: "Time to wind down — an early night is good for you 😴")
        }
    }

    var displayName: String {
        switch self {
        case .water:   return "Water"
        case .posture: return "Posture"
        case .sleep:   return "Sleep"
        }
    }

    var symbol: String {
        switch self {
        case .water:   return "drop.fill"
        case .posture: return "figure.stand"
        case .sleep:   return "moon.zzz.fill"
        }
    }

    /// Interval reminders fire on a cadence; sleep is a fixed time-of-day.
    var isIntervalBased: Bool { self != .sleep }
}

// MARK: - Manager

@MainActor
final class HealthReminderManager: ObservableObject {
    static let shared = HealthReminderManager()

    /// How many one-shot fires we keep queued ahead for interval reminders.
    /// Notification center allows up to 64 pending requests total; we stay well under.
    private let lookaheadCount = 12
    private let refillThreshold = 4

    private var cancellables = Set<AnyCancellable>()

    private init() {
        observeDefaults()
        startRefillMonitor()
    }

    // MARK: Public API

    /// Re-arm every enabled reminder. Call at app launch and whenever settings change.
    func rearm() {
        NotificationManager.shared.requestAuthorizationIfNeeded()
        for kind in HealthReminderKind.allCases {
            reschedule(kind)
        }
    }

    /// Re-arm a single reminder (cancel its pending fires, then re-schedule if enabled).
    func reschedule(_ kind: HealthReminderKind) {
        cancelAll(for: kind)
        guard isEnabled(kind) else { return }
        if kind.isIntervalBased {
            scheduleInterval(kind)
        } else {
            scheduleSleep()
        }
    }

    // MARK: Settings accessors (typed convenience over Defaults)

    func isEnabled(_ kind: HealthReminderKind) -> Bool {
        switch kind {
        case .water:   return Defaults[.waterEnabled]
        case .posture: return Defaults[.postureEnabled]
        case .sleep:   return Defaults[.sleepEnabled]
        }
    }

    // MARK: Interval scheduling (water / posture)

    private func scheduleInterval(_ kind: HealthReminderKind) {
        let intervalMinutes = max(1, interval(for: kind))
        let step = TimeInterval(intervalMinutes * 60)
        let sound = soundEnabled

        let now = Date()
        var fireDate = now.addingTimeInterval(step)
        var scheduled = 0
        var guardCounter = 0
        // A narrow active window combined with a one-minute interval can require walking
        // across multiple days before twelve valid fire dates are found.
        let stepsPerDay = (24 * 60 / intervalMinutes) + 1
        let maxIterations = max(lookaheadCount * 8, stepsPerDay * lookaheadCount)
        // Walk forward, emitting one-shot fires that land inside the active window,
        // skipping any that fall in quiet hours. Cap iterations so a tiny window
        // can't loop forever.
        while scheduled < lookaheadCount && guardCounter < maxIterations {
            guardCounter += 1
            if isWithinActiveHours(fireDate) {
                let delay = fireDate.timeIntervalSince(now)
                if delay >= 1 {
                    NotificationManager.shared.schedule(
                        id: "\(kind.notificationIDPrefix).\(scheduled)",
                        title: kind.title,
                        body: kind.body,
                        after: delay,
                        sound: sound
                    )
                    scheduled += 1
                }
            }
            fireDate = fireDate.addingTimeInterval(step)
        }
    }

    // MARK: Sleep scheduling (fixed time-of-day)

    private func scheduleSleep() {
        NotificationManager.shared.scheduleDaily(
            id: HealthReminderKind.sleep.notificationIDPrefix,
            title: HealthReminderKind.sleep.title,
            body: HealthReminderKind.sleep.body,
            hour: Defaults[.sleepHour],
            minute: Defaults[.sleepMinute],
            sound: soundEnabled
        )
    }

    // MARK: Cancellation

    private func cancelAll(for kind: HealthReminderKind) {
        if kind.isIntervalBased {
            // Cancel a generous range of indexed ids (covers any previous lookahead size).
            for i in 0..<(lookaheadCount * 4) {
                NotificationManager.shared.cancel(id: "\(kind.notificationIDPrefix).\(i)")
            }
        } else {
            NotificationManager.shared.cancel(id: kind.notificationIDPrefix)
        }
    }

    // MARK: Helpers

    private var soundEnabled: Bool { Defaults[.reminderSound] }

    private func interval(for kind: HealthReminderKind) -> Int {
        switch kind {
        case .water:   return Defaults[.waterIntervalMinutes]
        case .posture: return Defaults[.postureIntervalMinutes]
        case .sleep:   return 0
        }
    }

    /// True if `date`'s local time is inside the active-hours window (outside quiet hours).
    /// The window is [startHour:startMinute, endHour:endMinute). It may wrap past midnight
    /// (e.g. 22:00 → 07:00), in which case "inside" means times after start OR before end.
    private func isWithinActiveHours(_ date: Date) -> Bool {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let minutesOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        let start = Defaults[.activeStartHour] * 60 + Defaults[.activeStartMinute]
        let end = Defaults[.activeEndHour] * 60 + Defaults[.activeEndMinute]

        if start == end { return true } // empty/degenerate window => always active
        if start < end {
            return minutesOfDay >= start && minutesOfDay < end
        } else {
            // wraps midnight
            return minutesOfDay >= start || minutesOfDay < end
        }
    }

    // MARK: Defaults observation

    /// Re-arm automatically whenever any relevant setting changes. Debounced so a flurry
    /// of edits (dragging a stepper) results in a single reschedule.
    ///
    /// We merge per-key publishers (each emits its own change type) into a single Void
    /// stream. The single-key `Defaults.publisher(_:)` form is the most broadly available
    /// overload across Defaults versions.
    private func observeDefaults() {
        let streams: [AnyPublisher<Void, Never>] = [
            Defaults.publisher(.waterEnabled).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.waterIntervalMinutes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.postureEnabled).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.postureIntervalMinutes).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.sleepEnabled).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.sleepHour).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.sleepMinute).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.activeStartHour).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.activeStartMinute).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.activeEndHour).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.activeEndMinute).map { _ in () }.eraseToAnyPublisher(),
            Defaults.publisher(.reminderSound).map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(streams)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.rearm() }
            }
            .store(in: &cancellables)
    }

    /// Replenish interval reminders before the finite one-shot queue runs dry. Re-arming only
    /// when four or fewer requests remain preserves the existing cadence instead of pushing it
    /// forward on every timer tick.
    private func startRefillMonitor() {
        Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refillIntervalsIfNeeded() }
            .store(in: &cancellables)
    }

    private func refillIntervalsIfNeeded() {
        for kind in HealthReminderKind.allCases where kind.isIntervalBased && isEnabled(kind) {
            NotificationManager.shared.pendingRequestCount(withPrefix: kind.notificationIDPrefix) { [weak self] count in
                guard let self, self.isEnabled(kind), count <= self.refillThreshold else { return }
                self.reschedule(kind)
            }
        }
    }
}

// MARK: - Defaults keys

extension Defaults.Keys {
    // Water
    static let waterEnabled = Key<Bool>("notchpet.reminder.water.enabled", default: false)
    static let waterIntervalMinutes = Key<Int>("notchpet.reminder.water.intervalMinutes", default: 60)

    // Posture / sedentary
    static let postureEnabled = Key<Bool>("notchpet.reminder.posture.enabled", default: false)
    static let postureIntervalMinutes = Key<Int>("notchpet.reminder.posture.intervalMinutes", default: 45)

    // Sleep (time-of-day)
    static let sleepEnabled = Key<Bool>("notchpet.reminder.sleep.enabled", default: false)
    static let sleepHour = Key<Int>("notchpet.reminder.sleep.hour", default: 23)
    static let sleepMinute = Key<Int>("notchpet.reminder.sleep.minute", default: 0)

    // Shared active-hours window (quiet hours = outside this window). Default 08:00–22:00.
    static let activeStartHour = Key<Int>("notchpet.reminder.activeStartHour", default: 8)
    static let activeStartMinute = Key<Int>("notchpet.reminder.activeStartMinute", default: 0)
    static let activeEndHour = Key<Int>("notchpet.reminder.activeEndHour", default: 22)
    static let activeEndMinute = Key<Int>("notchpet.reminder.activeEndMinute", default: 0)

    // Shared sound toggle
    static let reminderSound = Key<Bool>("notchpet.reminder.sound", default: true)
}
