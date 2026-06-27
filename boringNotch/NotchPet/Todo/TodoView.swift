//
//  TodoView.swift
//  NotchPet
//
//  The expanded-notch To-Do tab: a quick-add field plus a scrollable checklist
//  with inline completion, hover-to-delete, and optional due dates. Designed to
//  sit on the notch's black background (~560–640pt wide, ~170pt content height).
//

import SwiftUI
import Defaults

struct TodoView: View {
    @ObservedObject var manager = TodoManager.shared

    @Default(.todoShowCompleted) private var showCompleted
    @Default(.todoSort) private var sort

    @State private var newTitle: String = ""
    @FocusState private var addFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            addField
            Divider().background(Color.white.opacity(0.08))
            listOrEmpty
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("To-Do")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)

            if manager.remainingCount > 0 {
                Text("\(manager.remainingCount) left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Spacer(minLength: 4)

            // Quick show/hide-completed toggle, mirrored in settings.
            Button {
                showCompleted.toggle()
            } label: {
                Image(systemName: showCompleted ? "eye" : "eye.slash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help(showCompleted ? "Hide completed" : "Show completed")

            if manager.hasCompleted {
                Button {
                    withAnimation { manager.clearCompleted() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
                .help("Clear completed")
            }
        }
    }

    // MARK: Add field

    private var addField: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.45))

            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($addFieldFocused)
                .onSubmit(addCurrent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func addCurrent() {
        withAnimation { manager.add(title: newTitle) }
        newTitle = ""
        addFieldFocused = true   // keep typing for rapid entry
    }

    // MARK: List

    @ViewBuilder
    private var listOrEmpty: some View {
        let items = manager.displayedItems
        if items.isEmpty {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        TodoRow(item: item, manager: manager)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
            Text(showCompleted ? "No tasks yet" : "Nothing to do")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Text("Type above and press return")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Row

private struct TodoRow: View {
    let item: TodoItem
    @ObservedObject var manager: TodoManager

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            // Checkbox
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { manager.toggleDone(item) }
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.done ? Color.accentColor : Color.white.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(item.done ? .white.opacity(0.4) : .white.opacity(0.92))
                    .strikethrough(item.done, color: .white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let due = item.due {
                    Label(dueText(due), systemImage: "calendar")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(dueColor(due, done: item.done))
                }
            }

            Spacer(minLength: 4)

            // Hover-to-delete
            if hovering {
                Button {
                    withAnimation { manager.delete(item) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help("Delete task")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Swipe-to-delete via context menu (the notch list isn't a UITableView).
        .contextMenu {
            Button(item.done ? "Mark as not done" : "Mark as done") {
                manager.toggleDone(item)
            }
            Button("Delete", role: .destructive) {
                manager.delete(item)
            }
        }
    }

    private func dueText(_ due: Date) -> String {
        let fmt = DateFormatter()
        if Calendar.current.isDateInToday(due) {
            fmt.dateFormat = "'Today' HH:mm"
        } else if Calendar.current.isDateInTomorrow(due) {
            fmt.dateFormat = "'Tomorrow' HH:mm"
        } else {
            fmt.dateFormat = "MMM d, HH:mm"
        }
        return fmt.string(from: due)
    }

    private func dueColor(_ due: Date, done: Bool) -> Color {
        if done { return .white.opacity(0.3) }
        return due.timeIntervalSinceNow < 0 ? .red.opacity(0.8) : .white.opacity(0.5)
    }
}

#if DEBUG
#Preview {
    TodoView()
        .frame(width: 600, height: 145)
        .background(Color.black)
}
#endif
