// Domain/LocalePreference.swift — app_shell bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/app_shell/schemas/locale_preference.cue
// ADR ref: ADR-0033, ADR-0039 (MEDIUM-04 — sanitised identifier)

// MARK: - DateStyle

public enum DateStyle: String, Sendable, Codable {
    case short, medium, long, full
}

// MARK: - TimeStyle

public enum TimeStyle: String, Sendable, Codable {
    case short, medium, long
}

// MARK: - NumberFormat

public enum NumberFormat: String, Sendable, Codable {
    case decimal
    case localeDefault = "locale_default"
}

// MARK: - LayoutDirection

public enum LayoutDirection: String, Sendable, Codable {
    case ltr, rtl, auto
}

// MARK: - LocalePreference

/// Operator-selected locale and formatting value object.
///
/// Persisted under `app_shell/locale_preference` in `local_persistence`.
/// The `LocaleResolverService` validates the `localeIdentifier` against a strict BCP 47 subset
/// (ADR-0039 MEDIUM-04) and falls back to `"en-US"` on mismatch.
public struct LocalePreference: Sendable, Codable {
    /// BCP 47 locale identifier validated against `^[a-zA-Z]{2,3}(-[A-Za-z]{2,4})?(-[A-Za-z]{4})?$`.
    public let localeIdentifier: String
    /// When `true`, tracks `Locale.preferredLanguages[0]` automatically.
    public let followSystem: Bool
    public let dateStyle: DateStyle
    public let timeStyle: TimeStyle
    /// IANA timezone identifier or `"system"`.
    public let timezone: String
    public let numberFormat: NumberFormat
    public let layoutDirection: LayoutDirection
    /// Optional override locale for CLDR plural category selection.
    public let pluralizationRule: String?

    /// Schema version tag for persistence migrations.
    public let schemaVersion: String

    public static let defaults = LocalePreference(
        localeIdentifier: "en-US",
        followSystem: true,
        dateStyle: .medium,
        timeStyle: .short,
        timezone: "system",
        numberFormat: .localeDefault,
        layoutDirection: .auto,
        pluralizationRule: nil,
        schemaVersion: "v1"
    )

    public init(
        localeIdentifier: String = "en-US",
        followSystem: Bool = true,
        dateStyle: DateStyle = .medium,
        timeStyle: TimeStyle = .short,
        timezone: String = "system",
        numberFormat: NumberFormat = .localeDefault,
        layoutDirection: LayoutDirection = .auto,
        pluralizationRule: String? = nil,
        schemaVersion: String = "v1"
    ) {
        self.localeIdentifier = localeIdentifier
        self.followSystem = followSystem
        self.dateStyle = dateStyle
        self.timeStyle = timeStyle
        self.timezone = timezone
        self.numberFormat = numberFormat
        self.layoutDirection = layoutDirection
        self.pluralizationRule = pluralizationRule
        self.schemaVersion = schemaVersion
    }

    /// Validates the identifier against the ADR-0039 allowed BCP 47 subset.
    public var isSanitizedIdentifier: Bool {
        let pattern = #"^[a-zA-Z]{2,3}(-[A-Za-z]{2,4})?(-[A-Za-z]{4})?$"#
        return localeIdentifier.range(of: pattern, options: .regularExpression) != nil
    }
}
