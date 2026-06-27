//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // NotchPet: out-of-sandbox file access for AI agent sync. The helper MUST
    // restrict these to paths under ~/.claude and ~/.clawd only.
    func readUserFile(_ path: String, maxBytes: Int, with reply: @escaping (Data?) -> Void)
    func writeUserFile(_ path: String, data: Data, executable: Bool, with reply: @escaping (Bool) -> Void)
    // NotchPet multi-agent: extract the vendored hook bundle and run its node installers
    // (restricted to ~/.notchpet). Lets NotchPet reuse clawd-on-desk's ready-made
    // per-agent installers for Codex/Cursor/Gemini/etc.
    func extractNotchpetArchive(_ archivePath: String, toDir: String, with reply: @escaping (Bool) -> Void)
    func runNotchpetNode(_ scriptPath: String, args: [String], with reply: @escaping (Int32, String) -> Void)
}

