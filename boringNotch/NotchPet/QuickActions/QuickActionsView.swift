//
//  QuickActionsView.swift
//  NotchPet
//
//  系统快捷指令 grid rendered inside the expanded notch. A LazyVGrid of tiles;
//  tapping a tile invokes its sandbox-safe action (see SystemActionsManager).
//

import SwiftUI
import Defaults

struct QuickActionsView: View {
    @ObservedObject var manager = SystemActionsManager.shared

    // Re-derive the visible set whenever the enable/order maps change.
    @Default(.quickActionsEnabled) private var enabledMap
    @Default(.quickActionsOrder) private var order

    /// Adaptive tile columns sized for the ~600pt-wide expanded notch. Smaller
    /// minimum keeps tiles compact so more fit per row in the short content area.
    private let columns = [GridItem(.adaptive(minimum: 70, maximum: 110), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header

            let actions = manager.visibleActions
            if actions.isEmpty {
                emptyState
            } else {
                // Single vertical ScrollView so extra rows scroll internally
                // instead of being clipped by the notch content area.
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(actions) { action in
                            ActionTile(action: action) { manager.run(action) }
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.yellow.opacity(0.9))
            Text("Quick Actions")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            // Inline, auto-clearing error feedback.
            if let error = manager.lastError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.9))
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.lastError)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 24))
                .foregroundStyle(.gray)
            Text("No actions enabled")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
            Text("Enable actions in Settings.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tile

private struct ActionTile: View {
    let action: QuickAction
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(systemName: action.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(height: 18)
                Text(action.title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(hovering ? 0.14 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(hovering ? 0.18 : 0.0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(action.help)
    }
}
