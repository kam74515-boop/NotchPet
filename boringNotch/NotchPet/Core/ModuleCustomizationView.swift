//
//  ModuleCustomizationView.swift
//  NotchPet
//
//  Nook-X-style component customization: choose which feature tabs appear in the
//  expanded notch, and drag to reorder. The tab bar fits up to 12 around the notch
//  (6 left + 6 right) without scrolling.
//

import SwiftUI
import Defaults

struct ModuleCustomizationView: View {
    @Default(.enabledModules) private var enabled
    @Default(.moduleOrder) private var order

    /// Modules in the user's chosen order (registry order as fallback).
    private var ordered: [NotchPetModule] {
        let all = NotchPetModuleRegistry.all
        guard !order.isEmpty else { return all }
        return all.sorted {
            (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max)
        }
    }

    /// Home is always shown; Shelf counts if enabled; plus the enabled feature modules.
    private var totalTabs: Int {
        var n = 1 // Home
        if Defaults[.boringShelf] { n += 1 }
        n += NotchPetModuleRegistry.all.filter { enabled[$0.id] ?? $0.defaultEnabled }.count
        return n
    }

    var body: some View {
        Form {
            Section {
                Text("Choose which components appear as tabs in the expanded notch, and drag to reorder. Up to 12 fit around the notch (6 left + 6 right) without scrolling.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("Tabs in use")
                    Spacer()
                    Text("\(totalTabs) / 12")
                        .foregroundStyle(totalTabs > 12 ? .orange : .secondary)
                        .monospacedDigit()
                }
                if totalTabs > 12 {
                    Label("More than 12 enabled — tabs past 12 won't be shown.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                List {
                    ForEach(ordered) { m in
                        Toggle(isOn: Binding(
                            get: { enabled[m.id] ?? m.defaultEnabled },
                            set: { newValue in
                                var e = enabled
                                e[m.id] = newValue
                                enabled = e
                            }
                        )) {
                            Label {
                                Text(LocalizedStringKey(m.label))
                            } icon: {
                                Image(systemName: m.icon)
                            }
                        }
                    }
                    .onMove { source, destination in
                        var ids = ordered.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        order = ids
                    }
                }
                .frame(minHeight: 320)
            } header: {
                Text("Components")
            } footer: {
                Text("Home is always shown first as the default page. Drag handles reorder; the order also controls which side of the notch each tab lands on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
