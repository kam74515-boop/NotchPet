//
//  PhotosSettingsView.swift
//  NotchPet
//
//  Settings pane for the Photos module: choose/clear the source folder,
//  toggle recursion, and adjust the grid thumbnail size.
//

import SwiftUI
import Defaults

struct PhotosSettingsView: View {
    @ObservedObject var manager = PhotoFolderManager.shared
    @Default(.photosThumbnailSize) private var thumbnailSize
    @Default(.photosRecursive) private var recursive
    @Default(.photosFolderPath) private var folderPath

    var body: some View {
        Form {
            Section("Source Folder") {
                HStack {
                    Image(systemName: manager.hasFolder ? "folder.fill" : "folder")
                        .foregroundStyle(manager.hasFolder ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        if manager.hasFolder, let url = manager.folderURL {
                            Text(url.lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                            Text(url.path)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else if !folderPath.isEmpty {
                            Text("Access lost — please re-select")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.orange)
                            Text(folderPath)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("No folder selected")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                HStack {
                    Button("Choose Folder…") { manager.chooseFolder() }
                    if manager.hasFolder {
                        Button("Refresh") { manager.refresh() }
                        Button(role: .destructive) { manager.clearFolder() } label: {
                            Text("Clear")
                        }
                    }
                }

                if let error = manager.errorMessage {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }

                Toggle("Include sub-folders", isOn: $recursive)
                    .onChange(of: recursive) { _, _ in
                        manager.refresh()
                    }
            }

            Section("Appearance") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Thumbnail size")
                        Spacer()
                        Text("\(Int(thumbnailSize)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $thumbnailSize, in: 48...120, step: 4) {
                        Text("Thumbnail size")
                    } minimumValueLabel: {
                        Image(systemName: "photo").imageScale(.small)
                    } maximumValueLabel: {
                        Image(systemName: "photo").imageScale(.large)
                    }
                }
            }

            if manager.hasFolder {
                Section {
                    LabeledContent("Images found", value: "\(manager.photos.count)")
                }
            }
        }
        .formStyle(.grouped)
    }
}
