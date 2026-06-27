//
//  TodoSettingsView.swift
//  NotchPet
//
//  Settings pane for the To-Do module: completed-item visibility and default
//  list ordering. Both bind directly to Defaults keys declared in TodoManager.
//

import SwiftUI
import Defaults

struct TodoSettingsView: View {
    @Default(.todoShowCompleted) private var showCompleted
    @Default(.todoSort) private var sort

    @ObservedObject private var manager = TodoManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show completed tasks", isOn: $showCompleted)

                Picker("Default sort", selection: $sort) {
                    ForEach(TodoSort.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("List")
            } footer: {
                if sort == .manual {
                    Text("Manual order lets you arrange tasks yourself; new tasks appear at the top.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Reordering is only available with Manual sort.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Open tasks", value: "\(manager.remainingCount)")
                LabeledContent("Total tasks", value: "\(manager.items.count)")

                Button("Clear completed tasks", role: .destructive) {
                    manager.clearCompleted()
                }
                .disabled(!manager.hasCompleted)
            } header: {
                Text("Maintenance")
            }
        }
        .formStyle(.grouped)
    }
}

#if DEBUG
#Preview {
    TodoSettingsView()
        .frame(width: 420, height: 360)
}
#endif
