// Domain/TypographyPreferences.swift — app_shell bounded context
// DDD role: ValueObject (#TypographyPreferences, #ResolvedTextStyle)
// CUE source: docs/arch/contexts/app_shell/schemas/typography_preferences.cue
// ADR ref: ADR-0021

// MARK: - UIScale

/// Uniform size multiplier applied on top of Dynamic Type scaling.
public enum UIScale: String, Sendable, Codable {
    case small, medium, large

    /// Numeric multiplier.
    public var multiplier: Double {
        switch self {
        case .small: return 0.875
        case .medium: return 1.0
        case .large: return 1.125
        }
    }
}

// MARK: - TextStyleRole

/// Semantic text style roles mapping to SwiftUI `Font.TextStyle` or fixed-size specs.
public enum TextStyleRole: String, Sendable, Codable, CaseIterable {
    case displayLarge, display, headline
    case body, subheadline, callout, footnote, caption
    case mono
}

// MARK: - ResolvedTextStyle (ReadModel)

/// Computed by `TypographyService` from `TypographyPreferences`; injected into SwiftUI environment.
///
/// Not persisted — recomputed on launch and on preference change.
public struct ResolvedTextStyle: Sendable, Codable {
    public let role: TextStyleRole
    /// Resolved PostScript family name.
    public let family: String
    /// Resolved point size (after `uiScale` multiplier; before Dynamic Type scaling).
    public let sizePoints: Double
    /// CSS-compatible weight name (maps to `Font.Weight`).
    public let weight: String
    /// Additional line spacing in points above the system default.
    public let lineSpacing: Double

    public init(role: TextStyleRole, family: String, sizePoints: Double, weight: String, lineSpacing: Double) {
        self.role = role
        self.family = family
        self.sizePoints = sizePoints
        self.weight = weight
        self.lineSpacing = lineSpacing
    }
}

// MARK: - TypographyPreferences

/// Operator-configurable knobs governing text rendering across the app shell.
///
/// Persisted under `app_shell/typography_preferences` in `local_persistence`.
public struct TypographyPreferences: Sendable, Codable {
    public var uiScale: UIScale
    /// PostScript family name. Validated at launch; falls back to `"SF Mono"` if unrecognised.
    public var monoFontFamily: String
    /// Base point size for mono text [10, 16]. `uiScale` is applied on top.
    public var monoBaseSizePoints: Int
    /// Scales with the system accessibility font size preference when `true`.
    public var useSystemDynamicType: Bool

    public static let defaults = TypographyPreferences(
        uiScale: .medium,
        monoFontFamily: "SF Mono",
        monoBaseSizePoints: 12,
        useSystemDynamicType: true
    )

    /// Permitted mono font family names per ADR-0021.
    public static let allowedMonoFamilies: Set<String> = [
        "SF Mono", "JetBrains Mono", "Berkeley Mono", "IBM Plex Mono"
    ]

    public init(
        uiScale: UIScale = .medium,
        monoFontFamily: String = "SF Mono",
        monoBaseSizePoints: Int = 12,
        useSystemDynamicType: Bool = true
    ) {
        self.uiScale = uiScale
        self.monoFontFamily = monoFontFamily
        self.monoBaseSizePoints = monoBaseSizePoints
        self.useSystemDynamicType = useSystemDynamicType
    }

    /// Base text style table for `uiScale: .medium` — scaled by `TypographyService`.
    public static let baseStyleTable: [ResolvedTextStyle] = [
        .init(role: .displayLarge, family: "SF Pro Display", sizePoints: 34, weight: "bold", lineSpacing: 0),
        .init(role: .display,      family: "SF Pro Display", sizePoints: 28, weight: "semibold", lineSpacing: 0),
        .init(role: .headline,     family: "SF Pro Display", sizePoints: 20, weight: "semibold", lineSpacing: 0),
        .init(role: .body,         family: "SF Pro Text",    sizePoints: 15, weight: "regular",  lineSpacing: 2),
        .init(role: .subheadline,  family: "SF Pro Text",    sizePoints: 13, weight: "semibold", lineSpacing: 1),
        .init(role: .callout,      family: "SF Pro Text",    sizePoints: 13, weight: "regular",  lineSpacing: 1),
        .init(role: .footnote,     family: "SF Pro Text",    sizePoints: 11, weight: "regular",  lineSpacing: 1),
        .init(role: .caption,      family: "SF Pro Text",    sizePoints: 10, weight: "regular",  lineSpacing: 0),
        .init(role: .mono,         family: "SF Mono",        sizePoints: 12, weight: "regular",  lineSpacing: 2),
    ]
}
