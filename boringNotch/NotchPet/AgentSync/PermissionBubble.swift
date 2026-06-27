//
//  PermissionBubble.swift
//  NotchPet — AI coding-agent task sync (permission bubbles)
//
//  Floating Allow/Deny bubble for Claude Code `PermissionRequest` HTTP hooks.
//  Only used when Defaults[.agentPermissionsEnabled] is on; otherwise the listener
//  returns "wait" and Claude Code keeps using its own terminal prompt.
//

import SwiftUI
import AppKit

@MainActor
final class PermissionBubbleController {
    static let shared = PermissionBubbleController()
    private var panel: NSPanel?
    private init() {}

    func present(_ payload: PermissionRequestPayload, respond: @escaping (PermissionDecision) -> Void) {
        dismiss()
        let size = NSSize(width: 360, height: 150)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PermissionBubbleView(payload: payload) { [weak self] decision in
            respond(decision)
            self?.dismiss()
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.maxY - size.height - 24))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct PermissionBubbleView: View {
    let payload: PermissionRequestPayload
    let onDecision: (PermissionDecision) -> Void

    private var detail: String {
        if let input = payload.rawJSON["tool_input"] as? [String: Any] {
            if let cmd = input["command"] as? String { return cmd }
            if let path = input["path"] as? String { return path }
            if let file = input["file_path"] as? String { return file }
        }
        return payload.toolName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                Text("Permission request").font(.headline)
                Spacer()
                Text(payload.toolName).font(.caption).foregroundStyle(.secondary)
            }
            Text(detail)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(3)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.9))
            HStack {
                Button("Deny") { onDecision(.deny) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Allow") { onDecision(.allow) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 360, height: 150)
        .background(RoundedRectangle(cornerRadius: 16).fill(.black.opacity(0.88)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
    }
}
