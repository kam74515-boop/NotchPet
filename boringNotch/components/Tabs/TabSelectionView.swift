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

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    /// Home + Shelf (built-ins) followed by the user-enabled NotchPet feature tabs.
    private var visibleTabs: [TabModel] {
        var result: [TabModel] = [TabModel(label: "Home", icon: "house.fill", view: .home)]
        if Defaults[.boringShelf] {
            result.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        }
        result.append(contentsOf: NotchPetModuleRegistry.enabledOrdered.map {
            TabModel(label: $0.label, icon: $0.icon, view: $0.view)
        })
        return result
    }

    var body: some View {
        // Horizontally scrollable so the row NEVER overflows the notch header,
        // no matter how many feature tabs the user enables.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(visibleTabs) { tab in
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
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
