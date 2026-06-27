//
//  NotesView.swift
//  NotchPet
//
//  Quick-notes scratchpad rendered inside the expanded notch. Left: a scrollable
//  list of notes with add/delete controls. Right: a TextEditor for the selected note.
//

import SwiftUI
import Defaults

struct NotesView: View {
    @ObservedObject var manager = NotesManager.shared

    @Default(.notesFontSize) private var fontSize
    @Default(.notesMonospaced) private var monospaced

    /// Local mirror of the selected note's text so typing feels instant; we push
    /// changes back to the manager (which debounces the actual persistence).
    @State private var draft: String = ""
    @FocusState private var editorFocused: Bool

    private var editorFont: Font {
        monospaced
            ? .system(size: CGFloat(fontSize), design: .monospaced)
            : .system(size: CGFloat(fontSize))
    }

    var body: some View {
        HStack(spacing: 10) {
            sidebar
                .frame(width: 180)

            Divider()
                .overlay(Color.white.opacity(0.12))

            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { syncDraftFromManager() }
        // Keep the editor in sync when the selection changes (e.g. clicking a row).
        .onChange(of: manager.selectedID) { _ in syncDraftFromManager() }
    }

    // MARK: - Sidebar (note list)

    private var sidebar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    commitDraft()
                    manager.addNote()
                    syncDraftFromManager()
                    editorFocused = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .help("New note")

                Button {
                    manager.deleteSelected()
                    syncDraftFromManager()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(manager.selectedID == nil ? .gray : .white.opacity(0.85))
                .disabled(manager.selectedID == nil)
                .help("Delete selected note")
            }

            if manager.notes.isEmpty {
                emptyList
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(manager.notes) { note in
                            noteRow(note)
                        }
                    }
                }
            }
        }
    }

    private var emptyList: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 22))
                .foregroundStyle(.gray)
            Text("No notes yet")
                .font(.system(size: 11))
                .foregroundStyle(.gray)
            Button("Create one") {
                manager.addNote()
                syncDraftFromManager()
                editorFocused = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.blue)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func noteRow(_ note: ScratchNote) -> some View {
        let isSelected = note.id == manager.selectedID
        return Button {
            guard note.id != manager.selectedID else { return }
            commitDraft()
            manager.select(note.id)
            syncDraftFromManager()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(for: note))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(relativeDate(note.updatedAt))
                        .foregroundStyle(.secondary)
                    if !previewBody(for: note).isEmpty {
                        Text(previewBody(for: note))
                            .foregroundStyle(.gray)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.white.opacity(0.14) : Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                manager.delete(id: note.id)
                syncDraftFromManager()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        if manager.selectedNote == nil {
            VStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 26))
                    .foregroundStyle(.gray)
                Text("Select or create a note")
                    .font(.system(size: 12))
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))

                TextEditor(text: $draft)
                    .font(editorFont)
                    .foregroundStyle(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($editorFocused)
                    .padding(8)
                    .onChange(of: draft) { newValue in
                        manager.updateSelected(text: newValue)
                    }

                // Placeholder shown when the note is empty.
                if draft.isEmpty {
                    Text("Type your note…")
                        .font(editorFont)
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Pull the manager's selected text into the local draft (without re-triggering a save).
    private func syncDraftFromManager() {
        draft = manager.selectedNote?.text ?? ""
    }

    /// Flush the in-flight draft to the manager before switching/creating notes.
    private func commitDraft() {
        guard manager.selectedNote != nil else { return }
        manager.updateSelected(text: draft)
    }

    private func displayTitle(for note: ScratchNote) -> String {
        // For the selected note, reflect the live draft so the title updates as you type.
        if note.id == manager.selectedID {
            return ScratchNote(text: draft).title
        }
        return note.title
    }

    private func previewBody(for note: ScratchNote) -> String {
        if note.id == manager.selectedID {
            return ScratchNote(text: draft).preview
        }
        return note.preview
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
