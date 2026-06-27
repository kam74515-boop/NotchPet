//
//  QuickActionsSettingsView.swift
//  NotchPet
//
//  Settings pane for 系统快捷指令: enable/disable each action and drag to reorder
//  which ones appear (and in what order) in the Quick Actions grid.
//

import SwiftUI
import Defaults

struct QuickActionsSettingsView: View {
    @ObservedObject private var manager = SystemActionsManager.shared

    // Observe persistence so the list reflects external changes / re-renders on edit.
    @Default(.quickActionsEnabled) private var enabledMap
    @Default(.quickActionsOrder) private var order

    var body: some View {
        Form {
            Section {
                // Edit-enabled list: drag handles reorder, toggles enable/disable.
                List {
                    ForEach(manager.orderedActions) { action in
                        row(for: action)
                    }
                    .onMove { manager.move(from: $0, to: $1) }
                }
                .environment(\.editMode, .constant(.active))
                .frame(minHeight: 260)
            } header: {
                Text("Actions")
            } footer: {
                Text("Toggle which actions appear in the grid. Drag to reorder. All actions are sandbox-safe and open System Settings panes or built-in tools.")
            }
        }
        .formStyle(.grouped)
    }

    private func row(for action: QuickAction) -> some View {
        // Per-row binding into the manager's enable map.
        let binding = Binding<Bool>(
            get: { manager.isEnabled(action) },
            set: { manager.setEnabled($0, for: action.id) }
        )

        return Toggle(isOn: binding) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                    Text(action.help)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: action.symbol)
                    .frame(width: 18)
            }
        }
        .toggleStyle(.switch)
    }
}
