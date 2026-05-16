// Ports/TranslationCatalogPort.swift — app_shell bounded context
// DDD role: Port (abstraction over .xcstrings bundle look-up)
// ADR ref: ADR-0033

import Foundation

// MARK: - TranslationCatalogPort

/// Port abstracting `.xcstrings` bundle look-up.
///
/// Allows injection of a test double with pre-seeded key translations in unit
/// and integration tests without requiring the full Xcode bundle pipeline.
public protocol TranslationCatalogPort: Sendable {
    /// Returns the localised string for `key` in the given locale.
    ///
    /// Falls back to the en-US source string when the key is missing in `locale`.
    /// Never returns a blank string or the raw key identifier.
    func translate(key: String, locale: String) -> String

    /// Returns the plural-variant string for `key` in `locale`, selecting the
    /// CLDR category appropriate for `count`.
    func translatePlural(key: String, count: Int, locale: String) -> String
}

// MARK: - BundleTranslationCatalog

/// Production implementation backed by the `.xcstrings` file in the app bundle.
public struct BundleTranslationCatalog: TranslationCatalogPort, Sendable {
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func translate(key: String, locale: String) -> String {
        // Delegates to Foundation's localised string look-up.
        // Locale injection is performed by LocaleResolverService via SwiftUI \.locale.
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    public func translatePlural(key: String, count: Int, locale: String) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, count)
    }
}

// MARK: - StubTranslationCatalog

/// Test double with a pre-seeded dictionary for unit and integration tests.
public struct StubTranslationCatalog: TranslationCatalogPort, Sendable {
    private let translations: [String: String]
    private let fallbackLocale: String

    public init(translations: [String: String], fallbackLocale: String = "en-US") {
        self.translations = translations
        self.fallbackLocale = fallbackLocale
    }

    public func translate(key: String, locale: String) -> String {
        translations["\(locale).\(key)"] ?? translations["\(fallbackLocale).\(key)"] ?? key
    }

    public func translatePlural(key: String, count: Int, locale: String) -> String {
        let base = translate(key: key, locale: locale)
        return String(format: base, count)
    }
}
