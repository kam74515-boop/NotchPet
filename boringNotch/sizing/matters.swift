//
//  sizeMatters.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 05/08/24.
//

import Defaults
import Foundation
import SwiftUI

let downloadSneakSize: CGSize = .init(width: 65, height: 1)
let batterySneakSize: CGSize = .init(width: 160, height: 1)

let shadowPadding: CGFloat = 20

/// Standard expanded-notch content height.
let standardOpenNotchHeight: CGFloat = 190
/// The Applications (Launcher) page expands ~3× taller so its app grid has room to breathe.
let launcherOpenNotchHeight: CGFloat = standardOpenNotchHeight * 3

/// Number of top tabs currently shown (Home + Shelf + enabled feature modules, capped at 12).
var notchTabCount: Int {
    let homeShelf = 1 + (Defaults[.boringShelf] ? 1 : 0)
    let features = NotchPetModuleRegistry.all.filter {
        Defaults[.enabledModules][$0.id] ?? $0.defaultEnabled
    }.count
    return min(12, homeShelf + features)
}

/// The expanded notch width is computed from the ACTUAL pieces it has to hold — the real notch
/// width, the tab icon size, and the gaps between icons — so the panel is never wider than it
/// needs to be. The notch must stay centred (the closed notch aligns to the physical notch, and
/// the window is centred on screen), so each side reserves the width of the WIDER side.
@MainActor
var openNotchSize: CGSize {
    let notchWidth = getClosedNotchSize().width      // real on-screen notch width

    // Keep these in sync with TabButton.frame / TabSelectionView spacing / BoringHeader padding.
    let tabW: CGFloat = 28        // TabButton .frame(width: 28) — the tab icon (svg) size
    let tabGap: CGFloat = 2       // gap between icons (TabSelectionView HStack spacing)
    let clusterPad: CGFloat = 4   // padding between a tab cluster and the notch

    let total = notchTabCount
    let leftCount = min(6, (total + 1) / 2)
    let rightCount = max(0, min(6, total - leftCount))
    func clusterWidth(_ n: Int) -> CGFloat {
        n > 0 ? CGFloat(n) * tabW + CGFloat(n - 1) * tabGap + clusterPad : 0
    }

    // Right-side function icons that are actually enabled (each a ~30-wide capsule + 4pt gap).
    var fn: CGFloat = 0
    if Defaults[.showMirror]           { fn += 34 }
    if Defaults[.settingsIconInNotch]  { fn += 34 }
    if Defaults[.showBatteryIndicator] { fn += 44 }

    let side = max(clusterWidth(leftCount), clusterWidth(rightCount) + fn)

    // CRUCIAL: when open, the panel insets its content horizontally so the tabs clear the rounded
    // shoulders (ContentView: .padding(.horizontal, opened.top) + .padding(.horizontal, 12)).
    // This inset is part of the panel width — omit it and the content overflows, clipping the
    // container and cutting off the corners. Mirror that exact padding here, per side.
    let panelHPad = (Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top
                                                    : cornerRadiusInsets.opened.bottom) + 12
    let sideMargin: CGFloat = 0                       // no extra slack per side (panelHPad already clears the shoulder)
    let tabDriven = notchWidth + 2 * side + 2 * panelHPad + 2 * sideMargin

    // Never narrower than what the body (music player etc.) needs to stay legible.
    let bodyMin: CGFloat = 480

    // Height grows when there's something tall to show: the Applications grid, or an in-notch
    // AskUserQuestion / permission card (so its options aren't clipped).
    let cap = (getScreenFrame()?.height ?? 900) - 140
    let coord = AgentSyncCoordinator.shared
    let height: CGFloat
    if BoringViewCoordinator.shared.currentView == .launcher {
        height = min(launcherOpenNotchHeight, cap)
    } else if let clar = coord.pendingClarification {
        // Prefer the card's MEASURED height so the notch fits it exactly (uniform margins, no inner
        // gap, no scroll). Above the card sits the BoringHeader (≈ notch-bar height) and the
        // AgentsTabView header; below it the panel's 12pt bottom pad — that's the fixed 'chrome'.
        let header = max(24, getClosedNotchSize().height)   // BoringHeader (tab bar) height
        let chrome = header + 46                             // tab-view header + spacings + bottom pads
        if coord.clarificationCardHeight > 1 {
            height = max(190, min(coord.clarificationCardHeight + chrome, cap))
        } else {
            // First frame before the card has reported its height — estimate from option count.
            let maxOptions = clar.questions.map { $0.options.count }.max() ?? 0
            let needed = chrome + 84 /*card header + title + question*/
                + CGFloat(maxOptions) * 48 /*options w/ description*/ + 40 /*custom*/ + 38 /*nav*/
            height = max(190, min(needed, cap))
        }
    } else if coord.pendingPermission != nil {
        height = min(280, cap)
    } else {
        height = standardOpenNotchHeight
    }
    return CGSize(width: max(bodyMin, tabDriven), height: height)
}

@MainActor
var windowSize: CGSize {
    .init(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
}
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

enum MusicPlayerImageSizes {
    static let cornerRadiusInset: (opened: CGFloat, closed: CGFloat) = (opened: 13.0, closed: 4.0)
    static let size = (opened: CGSize(width: 90, height: 90), closed: CGSize(width: 20, height: 20))
}

@MainActor func getScreenFrame(_ screenUUID: String? = nil) -> CGRect? {
    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }
    
    if let screen = selectedScreen {
        return screen.frame
    }
    
    return nil
}

@MainActor func getClosedNotchSize(screenUUID: String? = nil) -> CGSize {
    // Default notch size, to avoid using optionals
    var notchHeight: CGFloat = Defaults[.nonNotchHeight]
    var notchWidth: CGFloat = 185

    var selectedScreen = NSScreen.main

    if let uuid = screenUUID {
        selectedScreen = NSScreen.screen(withUUID: uuid)
    }

    // Check if the screen is available
    if let screen = selectedScreen {
        // Calculate and set the exact width of the notch
        if let topLeftNotchpadding: CGFloat = screen.auxiliaryTopLeftArea?.width,
           let topRightNotchpadding: CGFloat = screen.auxiliaryTopRightArea?.width
        {
            notchWidth = screen.frame.width - topLeftNotchpadding - topRightNotchpadding + 4
        }

        // Check if the Mac has a notch
        if screen.safeAreaInsets.top > 0 {
            // This is a display WITH a notch - use notch height settings
            notchHeight = Defaults[.notchHeight]
            if Defaults[.notchHeightMode] == .matchRealNotchSize {
                notchHeight = screen.safeAreaInsets.top
            } else if Defaults[.notchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        } else {
            // This is a display WITHOUT a notch - use non-notch height settings
            notchHeight = Defaults[.nonNotchHeight]
            if Defaults[.nonNotchHeightMode] == .matchMenuBar {
                notchHeight = screen.frame.maxY - screen.visibleFrame.maxY
            }
        }
    }

    return .init(width: notchWidth, height: notchHeight)
}
