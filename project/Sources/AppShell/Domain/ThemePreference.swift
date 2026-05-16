// Domain/ThemePreference.swift — app_shell bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/app_shell/schemas/theme_preference.cue
// ADR ref: ADR-0021

// MARK: - ColorScheme

/// Appearance mode for the application.
public enum AppColorScheme: String, Sendable, Codable {
    case system, light, dark
}

// MARK: - AccentSource

/// Source of the `accentBrand` color token.
public enum AccentSource: String, Sendable, Codable {
    case kubernetesBrand = "kubernetes_brand"
    case systemTint = "system_tint"
}

// MARK: - UIDensity

/// Vertical spacing rhythm for list rows, toolbar items, and form controls.
public enum UIDensity: String, Sendable, Codable {
    case compact, comfortable, spacious
}

// MARK: - SidebarDensity

/// Row height in the sidebar column.
public enum SidebarDensity: String, Sendable, Codable {
    /// 28 pt rows.
    case compact
    /// 36 pt rows (macOS default).
    case regular
}

// MARK: - ThemePreference

/// Operator-configurable appearance value object for the app shell.
///
/// Persisted under `app_shell/theme_preference` with `schemaVersion: "v1"`.
/// The `ThemePreferenceService` injects the resolved value into the SwiftUI environment
/// as a custom `EnvironmentKey`; views never access UserDefaults directly.
public struct ThemePreference: Sendable, Codable {
    public var colorScheme: AppColorScheme
    public var accentSource: AccentSource
    public var uiDensity: UIDensity
    public var sidebarDensity: SidebarDensity
    /// Disables non-essential animations. System `accessibilityReduceMotion` takes precedence.
    public var reduceMotion: Bool
    /// Enables Liquid Glass treatment on macOS 26+. Silently ignored on macOS 14/15.
    public var liquidGlassEnabled: Bool
    /// Persistence schema version tag.
    public let schemaVersion: String

    public static let defaults = ThemePreference(
        colorScheme: .system,
        accentSource: .kubernetesBrand,
        uiDensity: .comfortable,
        sidebarDensity: .regular,
        reduceMotion: false,
        liquidGlassEnabled: false,
        schemaVersion: "v1"
    )

    public init(
        colorScheme: AppColorScheme = .system,
        accentSource: AccentSource = .kubernetesBrand,
        uiDensity: UIDensity = .comfortable,
        sidebarDensity: SidebarDensity = .regular,
        reduceMotion: Bool = false,
        liquidGlassEnabled: Bool = false,
        schemaVersion: String = "v1"
    ) {
        self.colorScheme = colorScheme
        self.accentSource = accentSource
        self.uiDensity = uiDensity
        self.sidebarDensity = sidebarDensity
        self.reduceMotion = reduceMotion
        self.liquidGlassEnabled = liquidGlassEnabled
        self.schemaVersion = schemaVersion
    }
}
