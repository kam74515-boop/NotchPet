//
//  DesktopPet.swift
//  NotchPet — AI coding-agent task sync (desktop pet)
//
//  A floating, click-through pet that reacts to the aggregated agent state.
//  v1 is a native SwiftUI renderer (no external assets). Importing clawd-on-desk's
//  SVG/APNG theme packs via a WKWebView is a planned enhancement.
//

import SwiftUI
import AppKit

@MainActor
final class DesktopPetController {
    static let shared = DesktopPetController()
    private var panel: NSPanel?
    private init() {}

    func show() {
        if panel == nil { build() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let size = NSSize(width: 130, height: 130)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isMovableByWindowBackground = false

        let host = NSHostingView(rootView: DesktopPetView())
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.minY + 24))
        }
        self.panel = panel
    }
}

struct DesktopPetView: View {
    @ObservedObject var store = AgentSessionStore.shared
    @ObservedObject var coord = AgentSyncCoordinator.shared
    @State private var animate = false

    var body: some View {
        let state = coord.completionPeek?.state ?? store.displayState
        ZStack(alignment: .topTrailing) {
            Text("🦀")
                .font(.system(size: 68))
                .rotationEffect(.degrees(isBusy(state) ? (animate ? 7 : -7) : 0))
                .scaleEffect(state == .attention ? (animate ? 1.12 : 1.0) : 1.0)
                .shadow(color: state.tint.opacity(0.5), radius: state == .idle ? 0 : 10)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: animate)

            Image(systemName: state.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state.tint)
                .font(.system(size: 20, weight: .semibold))
                .padding(5)
                .background(Circle().fill(.black.opacity(0.65)))
                .offset(x: 8, y: -4)
                .opacity(state == .idle || state == .sleeping ? 0.0 : 1.0)
                .animation(.spring(response: 0.3), value: state)
        }
        .frame(width: 130, height: 130)
        .onAppear { animate = true }
        .help("AI agent: \(state.label)")
    }

    private func isBusy(_ s: AgentState) -> Bool {
        s == .working || s == .thinking || s == .juggling || s == .sweeping
    }
}
