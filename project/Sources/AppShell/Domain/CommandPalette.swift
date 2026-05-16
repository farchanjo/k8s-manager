// Domain/CommandPalette.swift — app_shell bounded context
// DDD role: AggregateRoot (#CommandPalette), ValueObject (#CommandEntry, #CommandInvocation, #KeyChord)
// CUE source: docs/arch/contexts/app_shell/schemas/command_palette.cue
// ADR ref: ADR-0023

import Foundation

// MARK: - KeyChord

/// A keyboard shortcut expressed as a set of modifiers and a base key.
///
/// Maps directly to SwiftUI `KeyEquivalent` + `EventModifiers` at the view layer.
public struct KeyChord: Sendable, Codable, Hashable {
    /// SwiftUI `EventModifiers` names (command, option, shift, control, function, capsLock, numericPad).
    public let modifiers: [String]
    /// Base key string — single character or named key (return, escape, delete, …).
    public let key: String

    public init(modifiers: [String], key: String) {
        self.modifiers = modifiers
        self.key = key
    }
}

// MARK: - CommandInvocation

/// Immutable record of a single command execution stored in the recent-invocations ring.
///
/// Stores only `commandId`, `invokedAt`, and `durationMillis` — no resource or cluster names.
public struct CommandInvocation: Sendable, Codable, Identifiable {
    /// Stable reference to `CommandEntry.id`.
    public let id: String
    /// RFC 3339 timestamp of the moment the operator pressed Return.
    public let invokedAt: String
    /// Wall-clock milliseconds from palette open to execution.
    public let durationMillis: Int

    public var commandId: String { id }

    public init(commandId: String, invokedAt: String, durationMillis: Int) {
        self.id = commandId
        self.invokedAt = invokedAt
        self.durationMillis = durationMillis
    }
}

// MARK: - CommandEntry

/// Immutable description of a single palette command.
///
/// Static entries are embedded in the app bundle; dynamic entries (pod names, cluster names)
/// are synthesised at palette open time.
public struct CommandEntry: Sendable, Codable, Identifiable {
    /// Kind of operation the palette routes on invocation.
    public enum Kind: String, Sendable, Codable {
        case navigation, action, resourceJump = "resource_jump", setting
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let subtitle: String?
    public let keywords: [String]
    public let keyboardShortcut: KeyChord?
    public let iconSFSymbol: String
    public let requiresContext: Bool

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        keywords: [String] = [],
        keyboardShortcut: KeyChord? = nil,
        iconSFSymbol: String,
        requiresContext: Bool
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.keyboardShortcut = keyboardShortcut
        self.iconSFSymbol = iconSFSymbol
        self.requiresContext = requiresContext
    }
}

// MARK: - FuzzyMatchConfig

/// Configuration for the fuzzy ranking algorithm used by the command palette.
public struct FuzzyMatchConfig: Sendable, Codable {
    /// Weight applied to the recency component of the frequency×recency score.
    public let recencyWeight: Double
    /// Weight applied to the frequency component.
    public let frequencyWeight: Double
    /// Maximum Levenshtein distance accepted as a fuzzy match.
    public let maxEditDistance: Int

    public static let `default` = FuzzyMatchConfig(
        recencyWeight: 0.6,
        frequencyWeight: 0.4,
        maxEditDistance: 3
    )

    public init(recencyWeight: Double, frequencyWeight: Double, maxEditDistance: Int) {
        self.recencyWeight = recencyWeight
        self.frequencyWeight = frequencyWeight
        self.maxEditDistance = maxEditDistance
    }
}

// MARK: - CommandPalette

/// Aggregate root for the universal command palette overlay.
///
/// Owns the open/closed lifecycle, the current query string, the selection cursor,
/// and the bounded ring of recent invocations (max 50).
/// Persisted under `app_shell/command_palette` in the `local_persistence` context.
public struct CommandPalette: Sendable, Codable, Identifiable {
    /// UUIDv7 stable aggregate identity.
    public let id: String
    /// Whether the palette overlay is currently presented.
    public var isOpen: Bool
    /// Current incremental search string.
    public var query: String
    /// Zero-based cursor position in the ranked result list.
    public var selectedIndex: Int
    /// Ring of at most 50 invocation records (newest first).
    public var recentInvocations: [CommandInvocation]
    /// Fuzzy-ranking configuration.
    public var fuzzyMatchConfig: FuzzyMatchConfig

    /// Invariant: `recentInvocations.count <= 50`.
    private static let maxRecents = 50

    public init(
        id: String,
        isOpen: Bool = false,
        query: String = "",
        selectedIndex: Int = 0,
        recentInvocations: [CommandInvocation] = [],
        fuzzyMatchConfig: FuzzyMatchConfig = .default
    ) {
        self.id = id
        self.isOpen = isOpen
        self.query = query
        self.selectedIndex = selectedIndex
        self.recentInvocations = recentInvocations
        self.fuzzyMatchConfig = fuzzyMatchConfig
    }

    /// Prepends an invocation record and evicts the oldest when the ring overflows.
    public mutating func recordInvocation(_ invocation: CommandInvocation) {
        recentInvocations.insert(invocation, at: 0)
        if recentInvocations.count > Self.maxRecents {
            recentInvocations.removeLast()
        }
    }
}
