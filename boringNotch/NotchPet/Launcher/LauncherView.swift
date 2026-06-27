//
//  LauncherView.swift
//  NotchPet
//
//  Launchpad-style grid of favorite apps shown inside the expanded notch.
//  Click an icon to launch; hover to reveal a remove badge; type to filter.
//

import SwiftUI
import Defaults

struct LauncherView: View {
    @ObservedObject var manager = AppLauncherManager.shared
    @Default(.launcherShowLabels) private var showLabels

    @State private var search: String = ""
    @State private var hoveredID: UUID?

    /// Favorites filtered by the live search text.
    private var filtered: [LauncherItem] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return manager.items }
        return manager.items.filter {
            $0.name.range(of: query, options: .caseInsensitive) != nil
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 50, maximum: 60), spacing: 6)]

    var body: some View {
        VStack(spacing: 6) {
            header

            if manager.items.isEmpty {
                emptyState
            } else if filtered.isEmpty {
                noResultsState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(filtered) { item in
                            iconCell(item)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Header (search + add)

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

            Button {
                manager.presentAddPanel()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("Add app…")
        }
    }

    // MARK: Icon cell

    private func iconCell(_ item: LauncherItem) -> some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Button {
                    manager.launch(item)
                } label: {
                    Image(nsImage: item.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 34, height: 34)
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(hoveredID == item.id ? Color.white.opacity(0.10) : .clear)
                        )
                }
                .buttonStyle(.plain)

                // Remove badge appears on hover.
                if hoveredID == item.id {
                    Button {
                        manager.remove(id: item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white, .red)
                            .background(Circle().fill(.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 2, y: -2)
                    .help("Remove \(item.name)")
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if showLabels {
                Text(item.name)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 54)
            }
        }
        .contextMenu {
            Button("Open") { manager.launch(item) }
            Divider()
            Button("Remove", role: .destructive) { manager.remove(id: item.id) }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
            }
        }
    }

    // MARK: Empty / no-results states

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No apps yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text("Add your favorite apps for one-click launching.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                manager.presentAddPanel()
            } label: {
                Label("Add app…", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
            Text("No matches for “\(search)”")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
