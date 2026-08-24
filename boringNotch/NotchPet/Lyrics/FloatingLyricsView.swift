//
//  FloatingLyricsView.swift
//  NotchPet
//
//  A translucent, NON-interactive lyric caption that floats just below the *closed* notch while
//  music is playing. The current line sits centered and bright; neighbours fade above/below and the
//  whole column scrolls vertically as the song advances — the same synced-lyric mechanism as the
//  full LyricsView, shrunk to a glanceable strip. It never intercepts clicks (allowsHitTesting is
//  false at the call site) and shows no progress bar. Turn it off from the notch's music player.
//

import AppKit
import Defaults
import SwiftUI

struct FloatingLyricsView: View {
    @ObservedObject var manager = MusicManager.shared
    @Default(.floatingLyricsColorData) private var colorData
    @Default(.floatingLyricsFontSize) private var fontSize

    /// Keep one neighbour on each side so the currently sung line remains in the visual centre.
    private let neighbourCount = 1

    private var lineHeight: CGFloat {
        max(CGFloat(fontSize) * 1.8, 28)
    }

    private var lyricColor: Color {
        guard let colorData,
              let color = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSColor.self,
                from: colorData
              ) else {
            return .white
        }
        return Color(nsColor: color)
    }

    var body: some View {
        // `.animation` re-renders each frame; we only recompute the derived index, which is cheap.
        TimelineView(.animation(minimumInterval: 0.2)) { context in
            let idx = currentLineIndex(at: context.date)
            let lines = manager.syncedLyrics
            ZStack(alignment: .center) {
                ForEach(visibleRange(around: idx, count: lines.count), id: \.self) { i in
                    line(lines[i].text, isCurrent: i == idx)
                        // Previous above, current in the middle, next below.
                        .offset(y: CGFloat(i - idx) * lineHeight)
                        .opacity(opacity(forDistance: i - idx))
                }
            }
            .frame(height: lineHeight * CGFloat(neighbourCount * 2 + 1), alignment: .center)
            .clipped()
            .animation(.easeInOut(duration: 0.35), value: idx)
        }
        .frame(maxWidth: .infinity)
        // Purely decorative — must not steal hover/clicks from the notch or the desktop.
        .allowsHitTesting(false)
    }

    private func line(_ text: String, isCurrent: Bool) -> some View {
        Text(text)
            .font(.system(
                size: isCurrent ? CGFloat(fontSize) : max(CGFloat(fontSize) - 2, 10),
                weight: isCurrent ? .bold : .semibold
            ))
            .foregroundStyle(isCurrent ? lyricColor : .white.opacity(0.72))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 420)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .scaleEffect(isCurrent ? 1 : 0.98)
            .shadow(color: .black.opacity(0.9), radius: 1, y: 1)
    }

    /// Signed distance from the current line: the outgoing line (above, d<0) fades toward the notch;
    /// upcoming lines (below, d>0) fade downward.
    private func opacity(forDistance d: Int) -> Double {
        switch d {
        case 0:            return 1.0
        case -1, 1:        return 1.0
        default:           return 0.0
        }
    }

    /// Previous + current + next, clamped to array bounds while preserving the centre position.
    private func visibleRange(around idx: Int, count: Int) -> [Int] {
        guard count > 0, idx >= 0 else { return [] }
        let lo = max(0, idx - 1)
        let hi = min(count - 1, idx + neighbourCount)
        guard lo <= hi else { return [] }
        return Array(lo...hi)
    }

    /// Index of the last line whose timestamp is <= the estimated playback position (-1 before the
    /// first line). Mirrors LyricsView's binary search.
    private func currentLineIndex(at date: Date) -> Int {
        let lines = manager.syncedLyrics
        guard !lines.isEmpty else { return -1 }
        let elapsed = manager.estimatedPlaybackPosition(at: date)
        var low = 0, high = lines.count - 1, idx = -1
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed { idx = mid; low = mid + 1 }
            else { high = mid - 1 }
        }
        return idx
    }
}
