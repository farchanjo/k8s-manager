// Domain/DesignTokens.swift — app_shell bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/app_shell/schemas/design_tokens.cue
// ADR ref: ADR-0021

// MARK: - ColorPair

/// A light/dark hex pair for a single color token.
///
/// Format: `"#rrggbb"` or `"system.<NSColorName>"`.
public struct ColorPair: Sendable, Codable, Hashable {
    public let light: String
    public let dark: String

    public init(light: String, dark: String) {
        self.light = light
        self.dark = dark
    }
}

// MARK: - ColorTokens

/// Canonical color token set for the K8sManager design system.
///
/// All hex values use six-character lowercase notation. Resolved into the
/// SwiftUI Color Asset Catalog at build time; no hardcoded hex appears in views.
public struct ColorTokens: Sendable, Codable {
    // Brand palette
    public let brandPrimaryLight: String
    public let brandPrimaryDark: String
    public let brandNavy: String
    public let brandSky: String

    // Semantic surface
    public let surfaceBackground: ColorPair
    public let surfaceElevated: ColorPair
    public let accentBrand: ColorPair

    // Semantic text
    public let textPrimary: ColorPair
    public let textSecondary: ColorPair
    public let textTertiary: ColorPair

    // Status
    public let statusHealthy: ColorPair
    public let statusWarning: ColorPair
    public let statusError: ColorPair
    public let statusTerminating: ColorPair
    public let statusUnknown: ColorPair

    // Kind accents
    public let kindAccentPod: ColorPair
    public let kindAccentDeploy: ColorPair
    public let kindAccentService: ColorPair
    public let kindAccentStorage: ColorPair
    public let kindAccentConfig: ColorPair
    public let kindAccentRBAC: ColorPair

    /// Default token values per `#DefaultColorTokens` in the CUE schema.
    public static let defaults = ColorTokens(
        brandPrimaryLight: "#326CE5", brandPrimaryDark: "#5E8FF0",
        brandNavy: "#0F3074", brandSky: "#9DB8E9",
        surfaceBackground: .init(light: "#FFFFFF", dark: "#1E1E1E"),
        surfaceElevated: .init(light: "#F5F5F5", dark: "#2A2A2A"),
        accentBrand: .init(light: "#326CE5", dark: "#5E8FF0"),
        textPrimary: .init(light: "#111111", dark: "#F0F0F0"),
        textSecondary: .init(light: "#555555", dark: "#AAAAAA"),
        textTertiary: .init(light: "#999999", dark: "#666666"),
        statusHealthy: .init(light: "#1A7F37", dark: "#3FB950"),
        statusWarning: .init(light: "#9A6700", dark: "#D29922"),
        statusError: .init(light: "#CF222E", dark: "#F85149"),
        statusTerminating: .init(light: "#BF7B00", dark: "#E3B341"),
        statusUnknown: .init(light: "#656D76", dark: "#8B949E"),
        kindAccentPod: .init(light: "#0550AE", dark: "#2F81F7"),
        kindAccentDeploy: .init(light: "#3B36C3", dark: "#7C72EA"),
        kindAccentService: .init(light: "#0D7377", dark: "#2CB9BB"),
        kindAccentStorage: .init(light: "#6B32B0", dark: "#B57AE7"),
        kindAccentConfig: .init(light: "#7D4617", dark: "#C67D3C"),
        kindAccentRBAC: .init(light: "#A41D5C", dark: "#E57BB2")
    )

    public init(
        brandPrimaryLight: String, brandPrimaryDark: String,
        brandNavy: String, brandSky: String,
        surfaceBackground: ColorPair, surfaceElevated: ColorPair, accentBrand: ColorPair,
        textPrimary: ColorPair, textSecondary: ColorPair, textTertiary: ColorPair,
        statusHealthy: ColorPair, statusWarning: ColorPair, statusError: ColorPair,
        statusTerminating: ColorPair, statusUnknown: ColorPair,
        kindAccentPod: ColorPair, kindAccentDeploy: ColorPair,
        kindAccentService: ColorPair, kindAccentStorage: ColorPair,
        kindAccentConfig: ColorPair, kindAccentRBAC: ColorPair
    ) {
        self.brandPrimaryLight = brandPrimaryLight
        self.brandPrimaryDark = brandPrimaryDark
        self.brandNavy = brandNavy
        self.brandSky = brandSky
        self.surfaceBackground = surfaceBackground
        self.surfaceElevated = surfaceElevated
        self.accentBrand = accentBrand
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.statusHealthy = statusHealthy
        self.statusWarning = statusWarning
        self.statusError = statusError
        self.statusTerminating = statusTerminating
        self.statusUnknown = statusUnknown
        self.kindAccentPod = kindAccentPod
        self.kindAccentDeploy = kindAccentDeploy
        self.kindAccentService = kindAccentService
        self.kindAccentStorage = kindAccentStorage
        self.kindAccentConfig = kindAccentConfig
        self.kindAccentRBAC = kindAccentRBAC
    }
}

// MARK: - MaterialTokens

/// SwiftUI `Material` identifiers for each structural surface. Fixed by ADR-0021.
public struct MaterialTokens: Sendable, Codable {
    public let sidebarMaterial: String
    public let contentMaterial: String
    public let inspectorMaterial: String
    public let popoverMaterial: String
    public let sheetMaterial: String

    public static let defaults = MaterialTokens(
        sidebarMaterial: "sidebar",
        contentMaterial: "regular",
        inspectorMaterial: "thin",
        popoverMaterial: "ultraThin",
        sheetMaterial: "thick"
    )

    public init(
        sidebarMaterial: String, contentMaterial: String,
        inspectorMaterial: String, popoverMaterial: String, sheetMaterial: String
    ) {
        self.sidebarMaterial = sidebarMaterial
        self.contentMaterial = contentMaterial
        self.inspectorMaterial = inspectorMaterial
        self.popoverMaterial = popoverMaterial
        self.sheetMaterial = sheetMaterial
    }
}

// MARK: - SpacingTokens

/// Discrete 4-pt-base spacing scale with semantic aliases.
public struct SpacingTokens: Sendable, Codable {
    public let scale: [Int]
    public let xsmall: Int
    public let small: Int
    public let medium: Int
    public let base: Int
    public let large: Int
    public let xlarge: Int

    public static let defaults = SpacingTokens(
        scale: [4, 8, 12, 16, 24, 32],
        xsmall: 4, small: 8, medium: 12, base: 16, large: 24, xlarge: 32
    )

    public init(scale: [Int], xsmall: Int, small: Int, medium: Int, base: Int, large: Int, xlarge: Int) {
        self.scale = scale
        self.xsmall = xsmall
        self.small = small
        self.medium = medium
        self.base = base
        self.large = large
        self.xlarge = xlarge
    }
}

// MARK: - RadiusTokens

/// Discrete corner-radius scale with semantic aliases.
public struct RadiusTokens: Sendable, Codable {
    public let scale: [Int]
    public let small: Int
    public let medium: Int
    public let large: Int

    public static let defaults = RadiusTokens(scale: [4, 8, 12], small: 4, medium: 8, large: 12)

    public init(scale: [Int], small: Int, medium: Int, large: Int) {
        self.scale = scale
        self.small = small
        self.medium = medium
        self.large = large
    }
}
