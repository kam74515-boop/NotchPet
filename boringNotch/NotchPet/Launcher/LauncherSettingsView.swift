//
//  LauncherSettingsView.swift
//  NotchPet
//
//  Settings pane for the Launcher module: toggle icon labels and manage the
//  favorites list (add / remove / reorder).
//

import SwiftUI
import Defaults

struct LauncherSettingsView: View {
    @ObservedObject var manager = AppLauncherManager.shared
    @Default(.launcherShowLabels) private var showLabels

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Show app names under icons", isOn: $showLabels)
            }

            Section {
                if manager.items.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(.secondary)
                            Text("No favorite apps yet")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    // Reorderable list of favorites with a per-row remove button.
                    List {
                        ForEach(manager.items) { item in
                            HStack(spacing: 10) {
                                Image(nsImage: item.icon)
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                Text(item.name)
                                    .lineLimit(1)
                                Spacer()
                                Button(role: .destructive) {
                                    manager.remove(id: item.id)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                                .help("Remove \(item.name)")
                            }
                        }
                        .onMove { source, destination in
                            manager.move(from: source, to: destination)
                        }
                    }
                    .frame(minHeight: 160)
                }
            } header: {
                HStack {
                    Text("Favorite Apps")
                    Spacer()
                    Button {
                        manager.presentAddPanel()
                    } label: {
                        Label("Add app…", systemImage: "plus")
                    }
                }
            } footer: {
                Text("Apps are stored as security-scoped bookmarks so they keep working after relaunch. Drag to reorder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
