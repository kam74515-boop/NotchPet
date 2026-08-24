//
//  HomeWidgetCustomizationView.swift
//  NotchPet
//
//  Settings pane to choose which widgets appear on the Home board and in what order
//  (Nook-X-style). Mirrors ModuleCustomizationView (toggle + drag-to-reorder + preview).
//

import SwiftUI
import Defaults

struct HomeWidgetCustomizationView: View {
    @Default(.homeWidgetsEnabled) private var enabled
    @Default(.homeWidgetsOrder) private var order

    private var ordered: [HomeWidgetKind] { HomeWidgetRegistry.allOrdered }
    private var enabledOrdered: [HomeWidgetKind] { HomeWidgetRegistry.enabledOrdered }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    if enabledOrdered.isEmpty {
                        Text("No widgets enabled")
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(enabledOrdered.prefix(5)) { w in
                            VStack(spacing: 3) {
                                Image(systemName: w.icon).font(.system(size: 14))
                                Text(LocalizedStringKey(w.label)).font(.system(size: 8)).lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 40)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.1)))
                        }
                        if enabledOrdered.count > 5 {
                            Text("+\(enabledOrdered.count - 5)")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.88)))
            } header: {
                Text("Preview")
            } footer: {
                Text("The Home page shows these widget cards, scrollable left-to-right.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                List {
                    ForEach(ordered) { w in
                        Toggle(isOn: Binding(
                            get: { enabled[w.id] ?? w.defaultEnabled },
                            set: { newValue in
                                var e = enabled
                                e[w.id] = newValue
                                enabled = e
                            }
                        )) {
                            Label {
                                Text(LocalizedStringKey(w.label))
                            } icon: {
                                Image(systemName: w.icon)
                            }
                        }
                    }
                    .onMove { source, destination in
                        var ids = ordered.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        order = ids
                    }
                }
                .frame(minHeight: 300)
            } header: {
                Text("Widgets")
            } footer: {
                Text("Toggle which widgets show on the Home page; drag to reorder them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
