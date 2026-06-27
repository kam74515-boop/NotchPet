//
//  PhotoFolderManager.swift
//  NotchPet
//
//  Folder-based photo browser (sandbox-friendly, no PhotoKit).
//  The user picks a folder via NSOpenPanel; we persist a security-scoped
//  bookmark in Defaults, resolve it on launch, and enumerate image files.
//

import SwiftUI
import AppKit
import Defaults
import UniformTypeIdentifiers

// MARK: - Defaults

extension Defaults.Keys {
    /// Security-scoped bookmark Data for the user-chosen photo folder (empty = none selected).
    static let photosFolderBookmark = Key<Data>("notchpet.photos.folderBookmark", default: Data())
    /// Last known display path of the chosen folder (for UI only; access still goes through the bookmark).
    static let photosFolderPath = Key<String>("notchpet.photos.folderPath", default: "")
    /// Thumbnail edge length in points (grid cell size). Clamped to a sensible range in the UI.
    static let photosThumbnailSize = Key<Double>("notchpet.photos.thumbnailSize", default: 72)
    /// Recurse into sub-folders when enumerating images.
    static let photosRecursive = Key<Bool>("notchpet.photos.recursive", default: false)
}

// MARK: - Model

/// A single discovered image file. `id` is the path so SwiftUI can diff stably.
struct PhotoItem: Identifiable, Hashable, Sendable {
    let url: URL
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

// MARK: - Manager

@MainActor
final class PhotoFolderManager: ObservableObject {
    static let shared = PhotoFolderManager()

    /// Discovered image items in the current folder (sorted by name).
    @Published private(set) var photos: [PhotoItem] = []
    /// Resolved folder URL we currently hold security-scoped access to (nil = none).
    @Published private(set) var folderURL: URL?
    /// True while an enumeration pass is in flight.
    @Published private(set) var isLoading = false
    /// Non-nil when the last operation failed (shown in the UI).
    @Published private(set) var errorMessage: String?

    /// Image content types we accept. WebP is matched by extension as a fallback
    /// because `UTType.webP` is unavailable on macOS 14.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "webp", "bmp"
    ]

    /// Whether we have started accessing the security-scoped resource (so we can balance the call).
    private var isAccessingScope = false

    private init() {
        resolveStoredFolder()
    }

    // Note: no deinit — this is a long-lived shared singleton, and we balance
    // security-scoped access in releaseCurrentScope()/clearFolder() instead.

    // MARK: Folder selection

    /// Whether a folder is currently selected and accessible.
    var hasFolder: Bool { folderURL != nil }

    /// Present an NSOpenPanel so the user can choose a directory, then persist a bookmark.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.title = "Choose a Photo Folder"
        panel.message = "Select a folder containing images to browse in the notch."

        let response = panel.runModal()
        guard response == .OK, let url = panel.urls.first else { return }

        do {
            // Security-scoped bookmark so access survives relaunch in the sandbox.
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            // Release any previous scope before adopting the new folder.
            releaseCurrentScope()
            Defaults[.photosFolderBookmark] = bookmark
            Defaults[.photosFolderPath] = url.path
            adopt(url: url)
        } catch {
            errorMessage = "Couldn't save access to that folder: \(error.localizedDescription)"
            NSLog("❌ PhotoFolderManager: bookmark failed for \(url.path): \(error.localizedDescription)")
        }
    }

    /// Forget the chosen folder and clear all loaded photos.
    func clearFolder() {
        releaseCurrentScope()
        Defaults[.photosFolderBookmark] = Data()
        Defaults[.photosFolderPath] = ""
        folderURL = nil
        photos = []
        errorMessage = nil
    }

    /// Re-run enumeration against the current folder (e.g. after the user adds files).
    func refresh() {
        guard let url = folderURL else { return }
        enumerate(folder: url)
    }

    // MARK: Startup resolution

    /// Resolve the stored bookmark (if any) and begin accessing + enumerating.
    private func resolveStoredFolder() {
        let data = Defaults[.photosFolderBookmark]
        guard !data.isEmpty else { return }

        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                // Refresh the bookmark so it keeps working across future launches.
                if let refreshed = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    Defaults[.photosFolderBookmark] = refreshed
                }
            }
            adopt(url: url)
        } catch {
            errorMessage = "Lost access to the saved folder. Please choose it again."
            NSLog("❌ PhotoFolderManager: failed to resolve bookmark: \(error.localizedDescription)")
            // Clear the broken bookmark so the UI returns to the "choose folder" state.
            Defaults[.photosFolderBookmark] = Data()
        }
    }

    /// Start security-scoped access for `url`, store it, and enumerate its images.
    private func adopt(url: URL) {
        isAccessingScope = url.startAccessingSecurityScopedResource()
        folderURL = url
        if !isAccessingScope {
            // We can sometimes still read freshly-picked folders even if this returns false,
            // so we continue, but surface a hint if enumeration later finds nothing.
            NSLog("⚠️ PhotoFolderManager: startAccessingSecurityScopedResource returned false for \(url.path)")
        }
        enumerate(folder: url)
    }

    private func releaseCurrentScope() {
        if isAccessingScope, let url = folderURL {
            url.stopAccessingSecurityScopedResource()
        }
        isAccessingScope = false
    }

    // MARK: Enumeration

    /// Enumerate image files in `folder` off the main actor, then publish results.
    private func enumerate(folder: URL) {
        isLoading = true
        errorMessage = nil
        let recursive = Defaults[.photosRecursive]
        let allowed = Self.imageExtensions

        Task.detached(priority: .userInitiated) {
            let found = Self.scan(folder: folder, recursive: recursive, allowed: allowed)
            await MainActor.run {
                self.photos = found
                self.isLoading = false
                // An empty result is a valid state; the view shows its own "no images" message.
            }
        }
    }

    /// Walk the directory and collect image URLs. Runs off the main actor.
    nonisolated private static func scan(folder: URL, recursive: Bool, allowed: Set<String>) -> [PhotoItem] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .nameKey]
        var results: [PhotoItem] = []

        func isImage(_ url: URL) -> Bool {
            allowed.contains(url.pathExtension.lowercased())
        }

        if recursive {
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            guard let enumerator = fm.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                options: options
            ) else { return [] }
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true, isImage(url) {
                    results.append(PhotoItem(url: url))
                }
            }
        } else {
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsSubdirectoryDescendants, .skipsPackageDescendants]
            guard let contents = try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: options
            ) else { return [] }
            for url in contents where isImage(url) {
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isRegularFile == true {
                    results.append(PhotoItem(url: url))
                }
            }
        }

        // Case-insensitive, locale-aware name sort for a predictable grid order.
        results.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return results
    }
}
