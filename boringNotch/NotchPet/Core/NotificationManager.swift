//
//  NotificationManager.swift
//  NotchPet
//
//  Thin wrapper around UNUserNotificationCenter shared by Pomodoro, health reminders,
//  to-do due alerts, and AI agent task-completion notifications. Works for an
//  LSUIElement (agent) app: willPresent returns .banner/.sound so banners appear.
//

import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    @Published private(set) var authorized = false

    private override init() {
        super.init()
        center.delegate = self
    }

    /// Request authorization once (idempotent). Safe to call at launch and lazily.
    func requestAuthorizationIfNeeded() {
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                Task { @MainActor in self?.authorized = true }
            case .notDetermined:
                self?.center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    Task { @MainActor in self?.authorized = granted }
                }
            default:
                Task { @MainActor in self?.authorized = false }
            }
        }
    }

    /// Fire a one-shot notification after `delay` seconds.
    func schedule(id: String = UUID().uuidString, title: String, body: String,
                  after delay: TimeInterval, sound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, delay), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// Schedule a repeating reminder at a fixed interval in seconds.
    /// (UNTimeIntervalNotificationTrigger requires >= 60s when repeating.)
    func scheduleRepeating(id: String, title: String, body: String,
                           interval: TimeInterval, sound: Bool = true) {
        cancel(id: id)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, interval), repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
