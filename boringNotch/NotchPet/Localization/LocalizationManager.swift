//
//  LocalizationManager.swift
//  NotchPet
//
//  In-app language switching that takes effect immediately (no restart). The chosen language is
//  stored in Defaults and applied two ways:
//    1. SwiftUI — root views read `\.locale` from this manager, so every `Text`/`Label` re-resolves
//       its String-Catalog entry against the selected language the moment it changes.
//    2. AppKit / NSLocalizedString — `Bundle.main` is swizzled to look strings up in the chosen
//       `.lproj`, so menus, notifications and any non-SwiftUI text follow along too.
//

import SwiftUI
import Defaults

extension Defaults.Keys {
    /// "system" (follow macOS) or a language code present in Localizable.xcstrings (e.g. "zh-Hans").
    static let appLanguage = Key<String>("notchpet.appLanguage", default: "system")
}

extension Notification.Name {
    static let appLanguageChanged = Notification.Name("notchpet.appLanguageChanged")
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// One selectable language. `code == "system"` means follow the OS preference.
    struct Language: Identifiable, Hashable {
        let code: String        // "system" or a catalog/.lproj code
        let nativeName: String  // shown in its own script
        var id: String { code }
    }

    /// "system" + every language the String Catalog ships. Order: system, 中文, English, then the rest.
    let languages: [Language] = [
        .init(code: "system",  nativeName: ""),               // label filled in localized in the UI
        .init(code: "zh-Hans", nativeName: "简体中文"),
        .init(code: "en",      nativeName: "English"),
        .init(code: "en-GB",   nativeName: "English (UK)"),
        .init(code: "ar",      nativeName: "العربية"),
        .init(code: "cs",      nativeName: "Čeština"),
        .init(code: "de",      nativeName: "Deutsch"),
        .init(code: "es",      nativeName: "Español"),
        .init(code: "fr",      nativeName: "Français"),
        .init(code: "hu",      nativeName: "Magyar"),
        .init(code: "it",      nativeName: "Italiano"),
        .init(code: "ko",      nativeName: "한국어"),
        .init(code: "pl",      nativeName: "Polski"),
        .init(code: "pt-BR",   nativeName: "Português (Brasil)"),
        .init(code: "ru",      nativeName: "Русский"),
        .init(code: "tr",      nativeName: "Türkçe"),
        .init(code: "uk",      nativeName: "Українська"),
    ]

    /// The selected language code ("system" or a concrete code). Published so SwiftUI roots rebuild.
    @Published private(set) var language: String

    private init() {
        language = Defaults[.appLanguage]
        applyBundle(for: language)
    }

    /// The concrete identifier to drive SwiftUI's `\.locale` with (resolves "system" to the OS choice).
    var localeIdentifier: String {
        if language == "system" {
            return Bundle.main.preferredLocalizations.first
                ?? Locale.preferredLanguages.first ?? "en"
        }
        return language
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }

    /// Right-to-left scripts so the UI can flip layout direction live.
    var layoutDirection: LayoutDirection {
        Locale.Language(identifier: localeIdentifier).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    func setLanguage(_ code: String) {
        guard code != language else { return }
        language = code
        Defaults[.appLanguage] = code
        applyBundle(for: code)
        // Keep AppleLanguages consistent so a future cold launch matches the in-app choice.
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        NotificationCenter.default.post(name: .appLanguageChanged, object: nil)
    }

    private func applyBundle(for code: String) {
        Bundle.setNotchPetLanguage(code == "system" ? nil : code)
    }
}

// MARK: - Root view wrapper (drives SwiftUI's locale live)

/// Wrap a window's root in this so the chosen language applies immediately. The `.id(language)`
/// forces a clean rebuild on change so every cached `Text` re-localizes.
struct LocalizedRoot<Content: View>: View {
    @ObservedObject private var loc = LocalizationManager.shared
    private let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .environment(\.locale, loc.locale)
            .environment(\.layoutDirection, loc.layoutDirection)
            .id(loc.language)
    }
}

// MARK: - Bundle language override (for NSLocalizedString / AppKit)

private var notchPetBundleKey: UInt8 = 0

/// Bundle subclass whose `localizedString` redirects into a specific `.lproj` when one is set.
private final class NotchPetLanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let path = objc_getAssociatedObject(self, &notchPetBundleKey) as? String,
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    /// Point `Bundle.main` at a language's `.lproj` (or back to the default when `nil`).
    static func setNotchPetLanguage(_ language: String?) {
        // Re-class the main bundle once so our override takes effect.
        if !(Bundle.main is NotchPetLanguageBundle) {
            object_setClass(Bundle.main, NotchPetLanguageBundle.self)
        }
        let path = language.flatMap { Bundle.main.path(forResource: $0, ofType: "lproj") }
        objc_setAssociatedObject(Bundle.main, &notchPetBundleKey, path, .OBJC_ASSOCIATION_RETAIN)
    }
}
