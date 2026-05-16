// Domain/IconCatalog.swift — app_shell bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/app_shell/schemas/icon_catalog.cue
// ADR ref: ADR-0028

// MARK: - IconRenderingMode

/// Controls how SwiftUI applies color to the symbol layers.
public enum IconRenderingMode: String, Sendable, Codable {
    case monochrome, hierarchical, palette, multicolor
}

// MARK: - IconVariant

/// Symbol variant applied via `.symbolVariant()`.
public enum IconVariant: String, Sendable, Codable {
    case `default`, fill, circle, square, slash
}

// MARK: - IconSemantic

/// Role of an icon in the information architecture.
public enum IconSemantic: String, Sendable, Codable {
    case kind, status, action, navigation, brand
}

// MARK: - IconEntry

/// One iconographic element in the catalog.
///
/// Every SwiftUI view must use an `id` from this catalog; no direct `systemName` references allowed.
public struct IconEntry: Sendable, Codable, Identifiable, Hashable {
    /// Stable kebab-case slug (used as Swift enum case by the code generator).
    public let id: String
    /// SF Symbols 6 stock name or `k8s.*` custom `.symbolset` name.
    public let symbolName: String
    /// How SwiftUI applies color to the symbol.
    public let renderingMode: IconRenderingMode
    /// Symbol variant modifier.
    public let variant: IconVariant
    /// VoiceOver announcement string (non-empty, natural language).
    public let accessibilityLabel: String
    /// Role in the information architecture.
    public let semantic: IconSemantic
    /// `true` for `.symbolset` assets in `Assets.xcassets`; referenced via `Image(symbolName:)`.
    public let isCustomSymbol: Bool
    /// Fallback symbol name for macOS 14 when the primary requires macOS 15+.
    public let macOS14FallbackName: String?

    public init(
        id: String,
        symbolName: String,
        renderingMode: IconRenderingMode = .hierarchical,
        variant: IconVariant = .default,
        accessibilityLabel: String,
        semantic: IconSemantic,
        isCustomSymbol: Bool = false,
        macOS14FallbackName: String? = nil
    ) {
        self.id = id
        self.symbolName = symbolName
        self.renderingMode = renderingMode
        self.variant = variant
        self.accessibilityLabel = accessibilityLabel
        self.semantic = semantic
        self.isCustomSymbol = isCustomSymbol
        self.macOS14FallbackName = macOS14FallbackName
    }
}

// MARK: - SymbolRenderHint

/// Attaches color and animation metadata to an `IconEntry` for a specific rendering context.
public struct SymbolRenderHint: Sendable, Codable {
    /// Ordered palette layer tint references (index 0 = primary layer).
    public let tints: [String]
    /// Symbol effect applied in this rendering context.
    public let animation: SymbolAnimation

    public enum SymbolAnimation: String, Sendable, Codable {
        case none, pulse, bounce, variableColor
    }

    public init(tints: [String], animation: SymbolAnimation = .none) {
        self.tints = tints
        self.animation = animation
    }
}

// MARK: - IconCatalog

/// Canonical registry of all symbol references used in K8sManager.
///
/// No SwiftUI view may reference a symbol name not declared here. Enforced via CI.
public struct IconCatalog: Sendable, Codable {
    /// Schema version — incremented on breaking changes.
    public let version: Int
    /// Ordered list of icon descriptors.
    public let entries: [IconEntry]

    /// Look up an entry by its slug.
    public func entry(id: String) -> IconEntry? {
        entries.first { $0.id == id }
    }

    public init(version: Int = 1, entries: [IconEntry]) {
        self.version = version
        self.entries = entries
    }
}
