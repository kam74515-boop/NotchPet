//
//  TodoManager.swift
//  NotchPet
//
//  Local-first to-do list. A single TodoManager singleton owns the persisted
//  array of TodoItem values (stored via the Defaults library). No EventKit /
//  network involvement — everything lives in UserDefaults.
//

import Foundation
import SwiftUI
import Defaults

// MARK: - Model

/// A single to-do entry. Codable + Defaults.Serializable so it can be stored
/// directly in a Defaults key as part of an array.
struct TodoItem: Identifiable, Codable, Hashable, Defaults.Serializable {
    let id: UUID
    var title: String
    var done: Bool
    var createdAt: Date
    /// Optional due date; when set in the future a notification is scheduled.
    var due: Date?

    init(id: UUID = UUID(),
         title: String,
         done: Bool = false,
         createdAt: Date = Date(),
         due: Date? = nil) {
        self.id = id
        self.title = title
        self.done = done
        self.createdAt = createdAt
        self.due = due
    }

    /// Stable notification identifier derived from the item id.
    var notificationID: String { "notchpet.todo.due.\(id.uuidString)" }
}

// MARK: - Sort options

/// How the list is ordered. `manual` preserves the user's drag order.
enum TodoSort: String, CaseIterable, Defaults.Serializable {
    case manual
    case createdNewest
    case createdOldest
    case dueDate
    case alphabetical

    var label: String {
        switch self {
        case .manual: return "Manual"
        case .createdNewest: return "Newest first"
        case .createdOldest: return "Oldest first"
        case .dueDate: return "Due date"
        case .alphabetical: return "A–Z"
        }
    }
}

// MARK: - Defaults keys

extension Defaults.Keys {
    /// The full list of to-do items (manual/storage order).
    static let todoItems = Key<[TodoItem]>("notchpet.todo.items", default: [])
    /// Whether completed items are shown in the list.
    static let todoShowCompleted = Key<Bool>("notchpet.todo.showCompleted", default: true)
    /// Default ordering applied to the displayed list.
    static let todoSort = Key<TodoSort>("notchpet.todo.sort", default: .manual)
}

// MARK: - Manager

@MainActor
final class TodoManager: ObservableObject {
    static let shared = TodoManager()

    /// Backing storage order (manual order). Views should read `displayedItems`
    /// for the user-facing, sorted/filtered list.
    @Published var items: [TodoItem] = []

    private init() {
        items = Defaults[.todoItems]
        // Keep in-memory state in sync if Defaults changes elsewhere.
        Task { [weak self] in
            for await newValue in Defaults.updates(.todoItems, initial: false) {
                guard let self else { return }
                if newValue != self.items { self.items = newValue }
            }
        }
    }

    // MARK: Derived state

    /// Items in the order/visibility configured by the user's settings.
    var displayedItems: [TodoItem] {
        let visible = Defaults[.todoShowCompleted] ? items : items.filter { !$0.done }
        return Self.sorted(visible, by: Defaults[.todoSort])
    }

    var remainingCount: Int { items.filter { !$0.done }.count }
    var hasCompleted: Bool { items.contains { $0.done } }

    private static func sorted(_ list: [TodoItem], by sort: TodoSort) -> [TodoItem] {
        switch sort {
        case .manual:
            return list
        case .createdNewest:
            return list.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest:
            return list.sorted { $0.createdAt < $1.createdAt }
        case .dueDate:
            // Items with a due date first (soonest first); undated sink to the bottom.
            return list.sorted { a, b in
                switch (a.due, b.due) {
                case let (.some(x), .some(y)): return x < y
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.createdAt < b.createdAt
                }
            }
        case .alphabetical:
            return list.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }

    // MARK: Mutations

    /// Add a new item from a raw title; trims whitespace and ignores empties.
    @discardableResult
    func add(title rawTitle: String, due: Date? = nil) -> TodoItem? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let item = TodoItem(title: title, due: due)
        items.insert(item, at: 0)
        persist()
        scheduleDueNotification(for: item)
        return item
    }

    func toggleDone(_ item: TodoItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].done.toggle()
        // Completed items shouldn't keep a pending due alert.
        if items[idx].done {
            NotificationManager.shared.cancel(id: items[idx].notificationID)
        } else {
            scheduleDueNotification(for: items[idx])
        }
        persist()
    }

    func delete(_ item: TodoItem) {
        NotificationManager.shared.cancel(id: item.notificationID)
        items.removeAll { $0.id == item.id }
        persist()
    }

    func updateTitle(_ item: TodoItem, to rawTitle: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].title = title
        persist()
    }

    func setDue(_ item: TodoItem, to due: Date?) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].due = due
        scheduleDueNotification(for: items[idx])
        persist()
    }

    /// Reorder within the manual list. `offsets`/`destination` come from a
    /// SwiftUI `.onMove`. Reordering is only meaningful in `.manual` sort.
    func move(from offsets: IndexSet, to destination: Int) {
        guard Defaults[.todoSort] == .manual else { return }
        // The visible list (with completed possibly hidden) maps onto `items`.
        let visible = Defaults[.todoShowCompleted] ? items : items.filter { !$0.done }
        var visibleIDs = visible.map(\.id)
        visibleIDs.move(fromOffsets: offsets, toOffset: destination)
        // Rebuild `items` honoring the new visible order, keeping hidden
        // (completed) items pinned in their original relative positions.
        reorderItems(toVisibleOrder: visibleIDs)
        persist()
    }

    /// Remove all completed items in one action.
    func clearCompleted() {
        for item in items where item.done {
            NotificationManager.shared.cancel(id: item.notificationID)
        }
        items.removeAll { $0.done }
        persist()
    }

    // MARK: Helpers

    private func reorderItems(toVisibleOrder visibleIDs: [UUID]) {
        let visibleSet = Set(visibleIDs)
        var ordered = visibleIDs.compactMap { id in items.first(where: { $0.id == id }) }
        // Append any items that weren't part of the visible set (e.g. hidden
        // completed items), preserving their existing order.
        let hidden = items.filter { !visibleSet.contains($0.id) }
        ordered.append(contentsOf: hidden)
        items = ordered
    }

    private func persist() {
        Defaults[.todoItems] = items
    }

    /// (Re)schedule a local notification for an item's due date if it's in the
    /// future and the item isn't done. Otherwise cancels any pending alert.
    private func scheduleDueNotification(for item: TodoItem) {
        let id = item.notificationID
        guard let due = item.due, !item.done, due.timeIntervalSinceNow > 0 else {
            NotificationManager.shared.cancel(id: id)
            return
        }
        NotificationManager.shared.requestAuthorizationIfNeeded()
        NotificationManager.shared.schedule(
            id: id,
            title: "To-Do due",
            body: item.title,
            after: due.timeIntervalSinceNow
        )
    }
}
