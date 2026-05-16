// Domain/I18nManifest.swift — app_shell bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/app_shell/schemas/i18n_manifest.cue
// ADR ref: ADR-0033

// MARK: - LocaleStatus

/// Quality level of a locale entry in the registry.
public enum LocaleStatus: String, Sendable, Codable {
    case stable, beta, incomplete
}

// MARK: - SupportedLocale

/// One entry in the locale registry combining baseline and extension locales.
public struct SupportedLocale: Sendable, Codable, Identifiable, Hashable {
    /// BCP 47 locale identifier (e.g. `"pt-BR"`, `"ar"`).
    public let identifier: String
    /// Own-script display name for the Settings → Language picker.
    public let displayName: String
    /// Fraction of translatable keys covered [0.0, 1.0].
    public let translationCoverage: Double
    /// GitHub handle of the maintainer.
    public let maintainer: String
    /// Application release version at which this locale was added.
    public let addedInVersion: String
    /// Current quality level.
    public let status: LocaleStatus

    public var id: String { identifier }

    /// `true` when coverage <0.80 — a warning badge is shown in the picker.
    public var showsCoverageWarning: Bool { translationCoverage < 0.80 }

    public init(
        identifier: String,
        displayName: String,
        translationCoverage: Double,
        maintainer: String,
        addedInVersion: String,
        status: LocaleStatus
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.translationCoverage = translationCoverage
        self.maintainer = maintainer
        self.addedInVersion = addedInVersion
        self.status = status
    }
}

// MARK: - TranslatableKey

/// Documentation and lint schema for a single `.xcstrings` key.
///
/// Not loaded at runtime; read by translator tooling from the CUE-exported JSON.
public struct TranslatableKey: Sendable, Codable {
    /// Dot-separated localisation key: `<bc>.<screen>.<element>.<purpose>`.
    public let keyPath: String
    /// Authoritative en-US source string.
    public let englishSource: String
    /// Optional translator hint (placement, constraints, character limits).
    public let contextHint: String?
    /// Whether this key has plural variants.
    public let pluralized: Bool
    /// CLDR plural category → English template string. Present when `pluralized`.
    public let plurals: [String: String]?

    public init(
        keyPath: String,
        englishSource: String,
        contextHint: String? = nil,
        pluralized: Bool = false,
        plurals: [String: String]? = nil
    ) {
        self.keyPath = keyPath
        self.englishSource = englishSource
        self.contextHint = contextHint
        self.pluralized = pluralized
        self.plurals = plurals
    }
}

// MARK: - I18nManifest

/// Top-level internationalisation registry (ADR-0033 governance contract).
///
/// The canonical instance is generated from `i18n_manifest.cue` at build time
/// and embedded in the app bundle. The Settings → Language picker reads from it.
public struct I18nManifest: Sendable, Codable {
    /// Source locale — always `"en-US"`.
    public let sourceLocale: String
    /// Baseline locales shipped and maintained by the core team (coverage must be 1.0).
    public let baselineLocales: [String]
    /// Community-maintained extension locales.
    public let extensionLocales: [SupportedLocale]

    /// Combined list of all known locales (baseline first, then extension).
    public var allLocales: [SupportedLocale] {
        let baseline = baselineLocales.map {
            SupportedLocale(
                identifier: $0,
                displayName: $0,
                translationCoverage: 1.0,
                maintainer: "@archanjo-team",
                addedInVersion: "1.0.0",
                status: .stable
            )
        }
        return baseline + extensionLocales
    }

    public init(
        sourceLocale: String = "en-US",
        baselineLocales: [String] = ["en", "pt-BR", "es-ES"],
        extensionLocales: [SupportedLocale] = []
    ) {
        self.sourceLocale = sourceLocale
        self.baselineLocales = baselineLocales
        self.extensionLocales = extensionLocales
    }
}
