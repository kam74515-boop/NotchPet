//
//  LauncherView.swift
//  NotchPet
//
//  macOS-Tahoe "应用程序" (Apps / Launchpad) style grid rendered inside the expanded notch,
//  on a black background. Apps are enumerated by the non-sandboxed XPC helper and bucketed
//  into category pills (效率与财务 / Developer Tools / 社交 / 工具 / 娱乐 / 创意 / 其他).
//  Click an icon to launch; pills filter by category; type to search.
//

import SwiftUI
import Defaults

struct LauncherView: View {
    @ObservedObject var manager = AppLauncherManager.shared

    enum Filter: Equatable { case all, category(AppCategory) }
    @State private var filter: Filter = .all
    @State private var search: String = ""

    /// The persistent "常用" (frequently-used) row at the top — most-recently-used apps, falling
    /// back to the auto-populated favorites so the row is never empty.
    private var frequentApps: [(id: String, url: URL, name: String, icon: NSImage)] {
        var seen = Set<String>()
        var result: [(id: String, url: URL, name: String, icon: NSImage)] = []
        func add(_ e: LauncherAppEntry) {
            guard seen.insert(e.id).inserted else { return }
            result.append((e.id, e.url, e.name, e.icon))
        }
        manager.recentApps.forEach(add)          // apps launched from NotchPet (instant feedback)
        manager.systemFrequentApps.forEach(add)  // then macOS's own frequently/recently-used apps
        if result.isEmpty {                      // last resort so the row is never empty
            return manager.items.prefix(8).map { ($0.url.path, $0.url, $0.name, $0.icon) }
        }
        return Array(result.prefix(8))
    }

    /// Category buckets that actually contain at least one app (pills shown only for these).
    private var availableCategories: [AppCategory] {
        let present = Set(manager.allApps.map(\.category))
        return AppCategory.allCases.filter { present.contains($0) }
    }

    /// Apps after the selected-filter + search filters.
    private var filtered: [LauncherAppEntry] {
        var apps: [LauncherAppEntry]
        switch filter {
        case .all:             apps = manager.allApps
        case .category(let c): apps = manager.allApps.filter { $0.category == c }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            apps = apps.filter { $0.name.range(of: query, options: .caseInsensitive) != nil }
        }
        return apps
    }

    private let columns = [GridItem(.adaptive(minimum: 56, maximum: 74), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if !frequentApps.isEmpty {
                frequentRow
            }
            if !manager.allApps.isEmpty {
                categoryPills
            }
            content
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .onAppear { Task { await manager.loadAllApps() } }
    }

    // MARK: Header (title + search + "…")

    private var header: some View {
        HStack(spacing: 8) {
            Text("Applications")
                .font(.system(size: 16, weight: .bold))

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .frame(maxWidth: 180)

            Spacer(minLength: 0)

            Menu {
                Button("Refresh") { Task { await manager.loadAllApps(force: true) } }
                Button("Add app…") { manager.presentAddPanel() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: Frequently-used row ("常用")

    private var frequentRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Frequently used")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            // Use the SAME columns + spacing as the main grid so the row aligns with it exactly.
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(frequentApps, id: \.id) { app in
                    appCell(url: app.url, name: app.name, icon: app.icon)
                }
            }
        }
        .padding(.bottom, 2)
    }

    // MARK: Category pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pill("All", isSelected: filter == .all) { filter = .all }
                ForEach(availableCategories) { cat in
                    pill(LocalizedStringKey(cat.label), isSelected: filter == .category(cat)) { filter = .category(cat) }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private func pill(_ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(isSelected ? 0.22 : 0.10)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        if manager.isLoadingApps && manager.allApps.isEmpty {
            loadingState
        } else if let error = manager.lastError, manager.allApps.isEmpty {
            errorState(error)
        } else if manager.allApps.isEmpty {
            emptyAppsState
        } else if filtered.isEmpty {
            noResultsState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filtered) { app in
                        cell(app)
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
        }
    }

    private func cell(_ app: LauncherAppEntry) -> some View {
        appCell(url: app.url, name: app.name, icon: app.icon)
    }

    /// Shared app tile used by both the "常用" row and the main grid (identical size + layout).
    private func appCell(url: URL, name: String, icon: NSImage) -> some View {
        Button { manager.launch(url: url) } label: {
            VStack(spacing: 3) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 42, height: 42)
                Text(name)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 66)
            }
        }
        .buttonStyle(.plain)
        .help(name)
    }

    // MARK: States

    private var loadingState: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            Text("Loading apps…")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            Button("Try Again") { Task { await manager.loadAllApps(force: true) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyAppsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.4))
            Text("No applications found")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            Button("Refresh") { Task { await manager.loadAllApps(force: true) } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20)).foregroundStyle(.white.opacity(0.4))
            Text(search.isEmpty ? "No apps in this category" : "No matches for “\(search)”")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
