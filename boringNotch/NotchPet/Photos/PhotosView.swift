//
//  PhotosView.swift
//  NotchPet
//
//  LazyVGrid of folder thumbnails rendered inside the expanded notch.
//  Tapping a thumbnail opens a Quick Look preview of the whole folder.
//

import SwiftUI
import AppKit
import Defaults

struct PhotosView: View {
    @ObservedObject var manager = PhotoFolderManager.shared
    @Default(.photosThumbnailSize) private var thumbnailSize

    /// The image currently shown in Quick Look (nil = panel closed).
    @State private var quickLookURL: URL?

    var body: some View {
        Group {
            if !manager.hasFolder {
                emptyState
            } else if manager.isLoading && manager.photos.isEmpty {
                loadingState
            } else if manager.photos.isEmpty {
                noImagesState
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // SwiftUI-native Quick Look: previews the tapped image within the folder set.
        .quickLookPreview($quickLookURL, in: manager.photos.map(\.url))
    }

    // MARK: Grid

    private var grid: some View {
        let cell = CGFloat(thumbnailSize)
        let columns = [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: 8)]

        return VStack(spacing: 0) {
            header
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(manager.photos) { photo in
                        PhotoThumbnailCell(photo: photo, edge: cell)
                            .onTapGesture { quickLookURL = photo.url }
                            .help(photo.name)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(manager.folderURL?.lastPathComponent ?? "Photos")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)
            Text("\(manager.photos.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            Spacer()
            Button {
                manager.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")

            Button {
                manager.chooseFolder()
            } label: {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Change folder")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: States

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("No photo folder selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Button(action: { manager.chooseFolder() }) {
                Label("Choose folder…", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            if let error = manager.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading photos…")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var noImagesState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text("No images in this folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            HStack(spacing: 10) {
                Button("Choose another…") { manager.chooseFolder() }
                    .font(.system(size: 11))
                Button("Refresh") { manager.refresh() }
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding()
    }
}

// MARK: - Thumbnail Cell

/// Renders a single thumbnail, loading it asynchronously via the shared ThumbnailService
/// (which caches results and handles security-scoped access internally).
private struct PhotoThumbnailCell: View {
    let photo: PhotoItem
    let edge: CGFloat

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: edge, height: edge)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else if failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: edge * 0.28))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: edge, height: edge)
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: photo.id) {
            await load()
        }
    }

    private func load() async {
        // Render at device scale for crisp thumbnails. ThumbnailService caches by url+size.
        let size = CGSize(width: edge, height: edge)
        let result = await ThumbnailService.shared.thumbnail(for: photo.url, size: size)
        if Task.isCancelled { return }
        if let result {
            image = result
        } else {
            failed = true
        }
    }
}
