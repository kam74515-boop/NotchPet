//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics
import CoreServices   // Spotlight MDItem — read each app's system usage (lastUsed / useCount)

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - NotchPet: restricted user-file access (~/.claude, ~/.clawd only)
    // The helper is NOT sandboxed, so it can read/write the user's real home dir.
    // We hard-restrict access to the two NotchPet directories to prevent a malicious
    // localhost POST in the main app from coercing arbitrary filesystem access.

    private func isAllowedNotchPetPath(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        let std = (path as NSString).standardizingPath
        let roots = [home + "/.claude", home + "/.clawd", home + "/.notchpet"]
        return roots.contains { std == $0 || std.hasPrefix($0 + "/") }
    }

    @objc func readUserFile(_ path: String, maxBytes: Int, with reply: @escaping (Data?) -> Void) {
        let std = (path as NSString).standardizingPath
        guard isAllowedNotchPetPath(std), let handle = FileHandle(forReadingAtPath: std) else {
            reply(nil); return
        }
        defer { try? handle.close() }
        if maxBytes <= 0 {
            reply(try? handle.readToEnd())
            return
        }
        // Bounded tail read for large transcript .jsonl files.
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        reply(try? handle.readToEnd())
    }

    @objc func writeUserFile(_ path: String, data: Data, executable: Bool, with reply: @escaping (Bool) -> Void) {
        let std = (path as NSString).standardizingPath
        guard isAllowedNotchPetPath(std) else { reply(false); return }
        let fm = FileManager.default
        let dir = (std as NSString).deletingLastPathComponent
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            // .atomic writes to a temp file in the same dir then renames into place.
            try data.write(to: URL(fileURLWithPath: std), options: .atomic)
            if executable {
                try fm.setAttributes([.posixPermissions: NSNumber(value: Int16(0o755))], ofItemAtPath: std)
            }
            reply(true)
        } catch {
            reply(false)
        }
    }

    @objc func extractNotchpetArchive(_ archivePath: String, toDir: String, with reply: @escaping (Bool) -> Void) {
        let a = (archivePath as NSString).standardizingPath
        let d = (toDir as NSString).standardizingPath
        guard isAllowedNotchPetPath(a), isAllowedNotchPetPath(d) else { reply(false); return }
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-xzf", a, "-C", d]
        do { try p.run(); p.waitUntilExit(); reply(p.terminationStatus == 0) }
        catch { reply(false) }
    }

    @objc func runNotchpetNode(_ scriptPath: String, args: [String], with reply: @escaping (Int32, String) -> Void) {
        let s = (scriptPath as NSString).standardizingPath
        guard isAllowedNotchPetPath(s) else { reply(-1, "path not allowed"); return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["node", s] + args
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = (env["PATH"].map { $0 + ":" + extra }) ?? extra
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            reply(p.terminationStatus, out)
        } catch {
            reply(-1, "\(error)")
        }
    }

    // Retained so the spawned monitor daemons aren't deallocated/terminated.
    private static var daemons: [Process] = []

    @objc func runNotchpetDaemon(_ scriptPath: String, args: [String], with reply: @escaping (Bool) -> Void) {
        let s = (scriptPath as NSString).standardizingPath
        guard isAllowedNotchPetPath(s) else { reply(false); return }
        let scriptName = (s as NSString).lastPathComponent

        // Kill any prior instance of this monitor (e.g. left over from a previous NotchPet launch).
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-f", scriptName]
        try? killer.run()
        killer.waitUntilExit()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["node", s] + args
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = (env["PATH"].map { $0 + ":" + extra }) ?? extra
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()                 // long-lived: do NOT waitUntilExit
            Self.daemons.append(p)
            reply(true)
        } catch {
            reply(false)
        }
    }

    // MARK: - NotchPet Launcher: enumerate installed apps (helper is NOT sandboxed)

    @objc func enumerateApplications(with reply: @escaping (Data?) -> Void) {
        let fm = FileManager.default
        // Same roots Launchpad draws from, plus per-user apps. The helper runs unsandboxed
        // as the user, so NSHomeDirectory() is the real home.
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
            NSHomeDirectory() + "/Applications",
        ]
        var seen = Set<String>()
        var apps: [[String: String]] = []

        func scan(_ dir: String, depth: Int) {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
            for entry in entries {
                let full = (dir as NSString).appendingPathComponent(entry)
                if entry.hasSuffix(".app") {
                    let std = (full as NSString).standardizingPath
                    guard seen.insert(std).inserted else { continue }
                    var bundleId = ""
                    var category = ""
                    let infoURL = URL(fileURLWithPath: std + "/Contents/Info.plist")
                    if let dict = NSDictionary(contentsOf: infoURL) {
                        bundleId = dict["CFBundleIdentifier"] as? String ?? ""
                        category = dict["LSApplicationCategoryType"] as? String ?? ""
                    }
                    // macOS's own usage stats via Spotlight, so the "常用" row matches what the
                    // system already considers frequently/recently used.
                    var lastUsed: Double = 0
                    var useCount: Double = 0
                    if let mdItem = MDItemCreate(nil, std as CFString) {
                        if let d = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date {
                            lastUsed = d.timeIntervalSince1970
                        }
                        if let n = MDItemCopyAttribute(mdItem, "kMDItemUseCount" as CFString) as? NSNumber {
                            useCount = n.doubleValue
                        }
                    }
                    apps.append([
                        "path": std, "bundleId": bundleId, "category": category,
                        "lastUsed": String(lastUsed), "useCount": String(useCount),
                    ])
                } else if depth > 0 {
                    // One level of vendor subfolders (e.g. /Applications/SomeVendor/App.app).
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                        scan(full, depth: depth - 1)
                    }
                }
            }
        }
        for root in roots { scan(root, depth: 1) }
        reply(try? JSONSerialization.data(withJSONObject: apps, options: []))
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}
