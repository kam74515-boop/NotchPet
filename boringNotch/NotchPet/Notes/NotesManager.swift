//
//  NotesManager.swift
//  NotchPet
//
//  Quick-notes scratchpad model + manager. Stores an array of ScratchNote in
//  Defaults with a debounced autosave so rapid keystrokes don't thrash UserDefaults.
//

import Foundation
import Combine
import Defaults

// MARK: - Model

/// A single scratchpad note. Codable + Defaults.Serializable so the whole
/// collection can be persisted directly through the Defaults library.
struct ScratchNote: Identifiable, Codable, Hashable, Defaults.Serializable {
    let id: UUID
    var text: String
    var updatedAt: Date

    init(id: UUID = UUID(), text: String = "", updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.updatedAt = updatedAt
    }

    /// First non-empty line, trimmed, used as the list row title.
    var title: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "New Note" }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? trimmed
        return firstLine.isEmpty ? "New Note" : firstLine
    }

    /// Short secondary line (the body after the title), used as a subtitle.
    var preview: String {
        let lines = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else { return "" }
        return lines.dropFirst()
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Defaults Keys

extension Defaults.Keys {
    /// The full collection of scratch notes.
    static let notesItems = Key<[ScratchNote]>("notchpet.notes.items", default: [])
    /// Id of the note that should be selected when the tab reopens.
    static let notesSelectedID = Key<String>("notchpet.notes.selectedID", default: "")
    /// Editor font size (points).
    static let notesFontSize = Key<Double>("notchpet.notes.fontSize", default: 13)
    /// Use a monospaced editor font when true.
    static let notesMonospaced = Key<Bool>("notchpet.notes.monospaced", default: false)
}

// MARK: - Manager

@MainActor
final class NotesManager: ObservableObject {
    static let shared = NotesManager()

    /// All notes, most-recently-updated first.
    @Published var notes: [ScratchNote] = []
    /// Currently selected note id (nil when nothing is selected / list is empty).
    @Published var selectedID: UUID?

    /// Debounce pipeline: edits push into this subject, and we persist after a
    /// short quiet period instead of writing on every keystroke.
    private let saveSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let stored = Defaults[.notesItems].sorted { $0.updatedAt > $1.updatedAt }
        notes = stored

        // Restore the previously selected note if it still exists.
        if let saved = UUID(uuidString: Defaults[.notesSelectedID]),
           stored.contains(where: { $0.id == saved }) {
            selectedID = saved
        } else {
            selectedID = stored.first?.id
        }

        // Debounced autosave: collapse bursts of edits into one write.
        saveSubject
            .debounce(for: .milliseconds(600), scheduler: RunLoop.main)
            .sink { [weak self] in self?.persist() }
            .store(in: &cancellables)
    }

    // MARK: Derived state

    var selectedNote: ScratchNote? {
        guard let id = selectedID else { return nil }
        return notes.first { $0.id == id }
    }

    private var selectedIndex: Int? {
        guard let id = selectedID else { return nil }
        return notes.firstIndex { $0.id == id }
    }

    // MARK: Mutations

    /// Create a fresh empty note, select it, and persist immediately.
    @discardableResult
    func addNote() -> ScratchNote {
        let note = ScratchNote()
        notes.insert(note, at: 0)
        selectedID = note.id
        persist()
        return note
    }

    /// Update the text of the currently selected note (debounced save).
    func updateSelected(text: String) {
        guard let index = selectedIndex else { return }
        guard notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        // Keep most-recent on top; re-sort but preserve selection.
        resortKeepingSelection()
        scheduleSave()
    }

    /// Delete a specific note by id.
    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        if selectedID == id {
            selectedID = notes.first?.id
        }
        persist()
    }

    /// Delete the currently selected note (used by the toolbar button).
    func deleteSelected() {
        guard let id = selectedID else { return }
        delete(id: id)
    }

    func select(_ id: UUID) {
        selectedID = id
        Defaults[.notesSelectedID] = id.uuidString
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveSubject.send(())
    }

    /// Write the current state to Defaults right away.
    private func persist() {
        Defaults[.notesItems] = notes
        Defaults[.notesSelectedID] = selectedID?.uuidString ?? ""
    }

    private func resortKeepingSelection() {
        let keepID = selectedID
        notes.sort { $0.updatedAt > $1.updatedAt }
        selectedID = keepID
    }
}
