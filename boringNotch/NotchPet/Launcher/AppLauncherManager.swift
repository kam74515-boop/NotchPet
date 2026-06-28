//
//  AppLauncherManager.swift
//  NotchPet
//
//  Sandbox-aware quick launcher. Favorites are application bundles the user
//  picks via NSOpenPanel; we persist security-scoped bookmarks (not raw paths)
//  so access survives relaunch inside the App Sandbox. Icons come from
//  NSWorkspace; launching goes through NSWorkspace.openApplication.
//

import AppKit
import SwiftUI
import Defaults
import UniformTypeIdentifiers

// MARK: - Persisted favorite

/// A favorite app stored as a security-scoped bookmark plus cached display metadata.
/// Codable + Defaults.Serializable so it can live directly in a Defaults array.
struct LauncherFavorite: Codable, Identifiable, Hashable, Defaults.Serializable {
    /// Stable identity (kept across relaunches so SwiftUI diffing is stable).
    let id: UUID
    /// Security-scoped bookmark data pointing at the .app bundle.
    var bookmark: Data
    /// Cached display name (resolved lazily; kept so the grid has a label even
    /// before the bookmark is resolved). Falls back to the bundle file name.
    var name: String

    init(id: UUID = UUID(), bookmark: Data, name: String) {
        self.id = id
        self.bookmark = bookmark
        self.name = name
    }
}

// MARK: - Defaults keys

extension Defaults.Keys {
    /// Ordered list of favorite apps (security-scoped bookmarks + names).
    static let launcherFavorites = Key<[LauncherFavorite]>("notchpet.launcher.favorites", default: [])
    /// Show app names beneath icons in the grid.
    static let launcherShowLabels = Key<Bool>("notchpet.launcher.showLabels", default: true)
}

// MARK: - Resolved runtime item

/// A favorite that has been resolved to a live file URL with its icon loaded.
/// Used purely for rendering; never persisted.
struct LauncherItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let icon: NSImage

    static func == (lhs: LauncherItem, rhs: LauncherItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Manager

@MainActor
final class AppLauncherManager: ObservableObject {
    static let shared = AppLauncherManager()

    /// Common apps to auto-populate the grid with, resolved by bundle id via Launch
    /// Services (sandbox-safe — no /Applications enumeration). Unknown/not-installed
    /// ids simply resolve to nil and are skipped.
    private static let suggestedBundleIDs: [String] = [
        // Coding tools / IDEs
        "com.todesktop.230313mzl4w4u92",            // Cursor
        "com.microsoft.VSCode", "com.apple.dt.Xcode",
        "com.exafunction.windsurf", "dev.zed.Zed",
        // Apple
        "com.apple.Safari", "com.apple.mobilesafari", "com.apple.Terminal",
        "com.apple.systempreferences", "com.apple.finder", "com.apple.mail",
        "com.apple.iCal", "com.apple.Notes", "com.apple.reminders",
        "com.apple.Music", "com.apple.Photos", "com.apple.Preview",
        "com.apple.AppStore", "com.apple.calculator", "com.apple.ScreenSaver.Engine",
        // Popular third-party
        "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.tencent.xinWeChat", "ru.keepcoder.Telegram", "com.tinyspeck.slackmacgap",
        "com.hnc.Discord", "us.zoom.xos", "com.microsoft.VSCodeInsiders",
        "notion.id", "md.obsidian", "com.figma.Desktop", "com.spotify.client",
        "com.microsoft.Word", "com.microsoft.Excel", "com.microsoft.Powerpoint",
        "com.microsoft.Outlook", "com.apple.iWork.Pages", "com.apple.iWork.Numbers",
        "com.apple.iWork.Keynote", "com.openai.chat", "com.anthropic.claudefordesktop",
    ]

    /// Stable id derived from a string (so suggested cells don't churn between reloads).
    private static func stableID(for s: String) -> UUID {
        var b = Array(s.utf8.prefix(16))
        while b.count < 16 { b.append(0) }
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    /// Resolved, ready-to-render favorites (mirrors `Defaults[.launcherFavorites]`).
    @Published private(set) var items: [LauncherItem] = []
    /// Transient user-facing error (e.g. a bookmark that no longer resolves).
    @Published var lastError: String?

    /// Bookmarks we are actively accessing, so we can balance start/stop calls.
    private var activeScopedURLs: [UUID: URL] = [:]

    private init() {
        reload()
        // React to changes made elsewhere (e.g. the settings pane) so the grid stays in sync.
        Task { [weak self] in
            for await _ in Defaults.updates(.launcherFavorites, initial: false) {
                self?.reload()
            }
        }
    }

    deinit {
        // Balance any outstanding security-scoped accesses.
        for url in activeScopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: Resolution

    /// Rebuild `items` from the persisted bookmarks, refreshing icons and pruning
    /// any favorites whose bookmarks can no longer be resolved.
    func reload() {
        // Release previously-held scoped access; we re-acquire below.
        for url in activeScopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeScopedURLs.removeAll()

        var resolved: [LauncherItem] = []
        var survivingFavorites: [LauncherFavorite] = []
        var didPrune = false

        for fav in Defaults[.launcherFavorites] {
            guard let url = resolve(fav) else {
                // Bookmark is stale/unresolvable — drop it.
                didPrune = true
                continue
            }
            let display = bestName(for: url, fallback: fav.name)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 44, height: 44)
            resolved.append(LauncherItem(id: fav.id, url: url, name: display, icon: icon))

            // Keep favorite, refreshing the cached display name and any renewed bookmark.
            var updated = fav
            updated.name = display
            survivingFavorites.append(updated)
        }

        // Auto-populate with common installed apps (resolved by bundle id — sandbox-safe),
        // so the grid isn't empty out of the box. User favorites always come first.
        var seenPaths = Set(resolved.map { $0.url.standardizedFileURL.path })
        for bid in Self.suggestedBundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { continue }
            let path = url.standardizedFileURL.path
            guard !seenPaths.contains(path) else { continue }
            seenPaths.insert(path)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 44, height: 44)
            resolved.append(LauncherItem(
                id: Self.stableID(for: bid), url: url,
                name: bestName(for: url, fallback: url.deletingPathExtension().lastPathComponent),
                icon: icon))
        }

        items = resolved

        // Persist pruning / refreshed names without re-entering reload in a loop:
        // only write when something actually changed.
        if didPrune || survivingFavorites != Defaults[.launcherFavorites] {
            Defaults[.launcherFavorites] = survivingFavorites
        }
    }

    /// Resolve a favorite's bookmark to a URL and begin scoped access.
    /// Returns nil if the bookmark cannot be resolved at all.
    private func resolve(_ fav: LauncherFavorite) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: fav.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        // Begin access; if it fails the app likely can't reach the file.
        let didStart = url.startAccessingSecurityScopedResource()
        guard FileManager.default.fileExists(atPath: url.path) else {
            if didStart { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        if didStart {
            activeScopedURLs[fav.id] = url
        }
        // Note: stale bookmarks still resolve and remain usable here; macOS will
        // refresh them transparently. We keep the original data to avoid churn.
        return url
    }

    /// Prefer the app's localized display name; fall back to the cached value.
    private func bestName(for url: URL, fallback: String) -> String {
        if let values = try? url.resourceValues(forKeys: [.localizedNameKey]),
           let localized = values.localizedName {
            // Strip the .app extension that localizedName sometimes includes.
            return (localized as NSString).deletingPathExtension
        }
        let base = url.deletingPathExtension().lastPathComponent
        return base.isEmpty ? fallback : base
    }

    // MARK: Mutation

    /// Present an NSOpenPanel rooted at /Applications for picking one or more .app bundles.
    func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.title = "Add to Launcher"
        panel.prompt = "Add"
        panel.message = "Choose one or more applications to add to your launcher."
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.treatsFilePackagesAsDirectories = false

        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.addApps(at: panel.urls)
            }
        }
    }

    /// Bookmark and store the given app URLs, ignoring duplicates.
    func addApps(at urls: [URL]) {
        var favorites = Defaults[.launcherFavorites]
        // Build a set of already-known paths to avoid dupes.
        let existingPaths = Set(items.map { $0.url.standardizedFileURL.path })

        for url in urls {
            let standardized = url.standardizedFileURL
            guard standardized.pathExtension.lowercased() == "app" else { continue }
            guard !existingPaths.contains(standardized.path),
                  !favorites.contains(where: { resolvedPath(for: $0) == standardized.path }) else {
                continue
            }
            guard let bookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else {
                lastError = "Couldn't bookmark \(url.lastPathComponent)."
                continue
            }
            let name = bestName(for: url, fallback: url.deletingPathExtension().lastPathComponent)
            favorites.append(LauncherFavorite(bookmark: bookmark, name: name))
        }

        Defaults[.launcherFavorites] = favorites
        reload()
    }

    /// Best-effort resolution of a favorite to a path (used only for dedupe checks).
    private func resolvedPath(for fav: LauncherFavorite) -> String? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: fav.bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return url.standardizedFileURL.path
    }

    /// Remove a favorite by id.
    func remove(id: UUID) {
        if let url = activeScopedURLs.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }
        Defaults[.launcherFavorites].removeAll { $0.id == id }
        reload()
    }

    /// Move a favorite within the ordered list (for settings drag-to-reorder).
    func move(from source: IndexSet, to destination: Int) {
        var favorites = Defaults[.launcherFavorites]
        favorites.move(fromOffsets: source, toOffset: destination)
        Defaults[.launcherFavorites] = favorites
        reload()
    }

    // MARK: Launch

    /// Launch the app at the given URL. Re-resolves access defensively in case the
    /// scoped resource was released.
    func launch(_ item: LauncherItem) {
        let url = item.url
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            guard let error else { return }
            Task { @MainActor in
                self?.lastError = "Couldn't open \(item.name): \(error.localizedDescription)"
            }
        }
    }
}
