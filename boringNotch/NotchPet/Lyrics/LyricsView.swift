//
//  LyricsView.swift
//  NotchPet
//
//  Full-view synced lyrics ("歌词全视图") rendered inside the expanded notch.
//
//  The data layer lives entirely in `MusicManager.shared`:
//    - `syncedLyrics: [(time: Double, text: String)]`  time-stamped LRC lines
//    - `currentLyrics: String`                          plain (unsynced) fallback text
//    - `isFetchingLyrics: Bool`                         network/AppleScript lookup in flight
//    - `estimatedPlaybackPosition(at:)`                 sleep-safe elapsed-time estimate
//
//  This view never mutates the manager; it only derives the active line index locally
//  from the synced-lyrics array and the estimated playback position, then drives a
//  `ScrollViewReader` to keep that line centered. A `TimelineView(.animation)` ticks the
//  recomputation so the highlight stays in sync without per-second decrement timers.
//

import SwiftUI
import Defaults

struct LyricsView: View {
    @ObservedObject var manager = MusicManager.shared
    @Default(.enableLyrics) private var enableLyrics

    var body: some View {
        Group {
            if !enableLyrics {
                disabledState
            } else if manager.isFetchingLyrics && manager.syncedLyrics.isEmpty && manager.currentLyrics.isEmpty {
                fetchingState
            } else if !manager.syncedLyrics.isEmpty {
                syncedLyricsBody
            } else if !manager.currentLyrics.isEmpty {
                plainLyricsBody
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
    }

    // MARK: - Synced (time-stamped) lyrics

    private var syncedLyricsBody: some View {
        // `.animation` schedule re-renders every frame; we throttle our own work by only
        // reacting when the derived line index actually changes (see SyncedScroller).
        TimelineView(.animation) { context in
            SyncedScroller(
                lines: manager.syncedLyrics,
                currentIndex: currentLineIndex(at: context.date),
                onSeek: { time in manager.seek(to: time) }
            )
        }
    }

    /// Index of the last line whose timestamp is <= the current estimated position.
    /// Returns -1 before the first line so the intro can stay dimmed.
    private func currentLineIndex(at date: Date) -> Int {
        let lines = manager.syncedLyrics
        guard !lines.isEmpty else { return -1 }
        let elapsed = manager.estimatedPlaybackPosition(at: date)

        // Binary search for the last line with time <= elapsed.
        var low = 0
        var high = lines.count - 1
        var idx = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return idx
    }

    // MARK: - Plain (unsynced) lyrics

    private var plainLyricsBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(plainLines.indices, id: \.self) { i in
                    Text(plainLines[i])
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    private var plainLines: [String] {
        manager.currentLyrics
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
    }

    // MARK: - Placeholder states

    private var fetchingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
            Text("Fetching lyrics…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            trackSubtitle
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
            Text(manager.songTitle.isEmpty ? "No lyrics available" : "No lyrics found")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            trackSubtitle
        }
    }

    private var disabledState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.badge.xmark")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
            Text("Lyrics are turned off")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text("Enable lyrics in Settings to see them here.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    /// "Title — Artist" subtitle shown under placeholder states.
    @ViewBuilder
    private var trackSubtitle: some View {
        let title = manager.songTitle.trimmingCharacters(in: .whitespaces)
        let artist = manager.artistName.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            Text(artist.isEmpty ? title : "\(title) — \(artist)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 24)
        }
    }
}

// MARK: - Synced scroller

/// Renders the synced-lyric lines and keeps the active one centered. Pulled out of the
/// `TimelineView` closure so its `onChange(of:)` fires only when the active index moves,
/// avoiding redundant scroll work on every animation frame.
private struct SyncedScroller: View {
    let lines: [(time: Double, text: String)]
    let currentIndex: Int
    let onSeek: (Double) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    // Top spacer lets the first line settle near the vertical center of
                    // the ~145pt notch panel (half the panel height, minus a line).
                    Color.clear.frame(height: 52)

                    ForEach(lines.indices, id: \.self) { i in
                        lineView(at: i)
                            .id(i)
                            .onTapGesture { onSeek(lines[i].time) }
                    }

                    // Bottom spacer mirrors the top so the last line can also center.
                    Color.clear.frame(height: 52)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: currentIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < lines.count else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onAppear {
                guard currentIndex >= 0, currentIndex < lines.count else { return }
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func lineView(at i: Int) -> some View {
        let isCurrent = i == currentIndex
        Text(lines[i].text)
            .font(.system(size: isCurrent ? 16 : 13,
                          weight: isCurrent ? .bold : .medium))
            .foregroundStyle(.white.opacity(opacity(for: i)))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .scaleEffect(isCurrent ? 1.0 : 0.96)
            .animation(.easeInOut(duration: 0.25), value: isCurrent)
    }

    /// Past lines fade slightly, future lines fade more, the current line is fully opaque.
    private func opacity(for i: Int) -> Double {
        if i == currentIndex { return 1.0 }
        if i < currentIndex { return 0.35 }      // already sung
        return 0.5                                // upcoming
    }
}
