//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

enum TabSide { case left, right }

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    /// Which side of the notch this row renders (tabs are split 6 left / 6 right).
    var side: TabSide = .left

    /// Home + Shelf (built-ins) followed by the user-enabled NotchPet feature tabs,
    /// capped at 12 (6 per side). The expanded notch widens to fit them.
    static var allVisibleTabs: [TabModel] {
        var result: [TabModel] = [TabModel(label: "Home", icon: "house.fill", view: .home)]
        if Defaults[.boringShelf] {
            result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        result.append(contentsOf: NotchPetModuleRegistry.enabledOrdered.map {
            TabModel(label: $0.label, icon: $0.icon, view: $0.view)
        })
        return Array(result.prefix(12))
    }

    private var sideTabs: [TabModel] {
        let all = Self.allVisibleTabs
        let leftCount = min(6, (all.count + 1) / 2)
        return side == .left ? Array(all.prefix(leftCount))
                             : Array(all.dropFirst(leftCount).prefix(6))
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(sideTabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    Capsule()
                        .fill(tab.view == coordinator.currentView ? Color(nsColor: .secondarySystemFill) : Color.clear)
                }
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
