// Domain/KeyboardShortcutMap.swift — app_shell bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/app_shell/schemas/keyboard_shortcut_map.cue
// ADR ref: ADR-0023

// MARK: - ShortcutScope

/// Panel focus context in which a shortcut binding is active.
public enum ShortcutScope: String, Sendable, Codable {
    case global
    case resourceBrowser = "resource_browser"
    case terminal
    case helm
    case metrics
    case analytics
}

// MARK: - ShortcutBinding

/// Associates a `KeyChord` with a command entry within a specific scope.
public struct ShortcutBinding: Sendable, Codable, Identifiable {
    /// Stable kebab-case slug (primary key in the help overlay).
    public let id: String
    /// References `CommandEntry.id`.
    public let commandId: String
    /// The keyboard combination that triggers this binding.
    public let keyChord: KeyChord
    /// Activation scope.
    public let scope: ShortcutScope
    /// Optional runtime predicate evaluated against `ApplicationFocusSnapshot`.
    public let whenContext: String?
    /// Human-readable label shown in the hotkey help overlay (≤80 chars, no trailing period).
    public let description: String

    public init(
        id: String,
        commandId: String,
        keyChord: KeyChord,
        scope: ShortcutScope,
        whenContext: String? = nil,
        description: String
    ) {
        self.id = id
        self.commandId = commandId
        self.keyChord = keyChord
        self.scope = scope
        self.whenContext = whenContext
        self.description = description
    }
}

// MARK: - KeyboardShortcutMap

/// Immutable registry of all shortcut bindings for the application shell.
///
/// Operator cannot rebind shortcuts in this version. Consumed by SwiftUI
/// `.keyboardShortcut` registrations at app startup.
public struct KeyboardShortcutMap: Sendable, Codable {
    /// All registered bindings ordered for help-overlay display.
    public let bindings: [ShortcutBinding]

    /// Returns all bindings active in a given scope.
    public func bindings(for scope: ShortcutScope) -> [ShortcutBinding] {
        bindings.filter { $0.scope == scope }
    }

    /// Checks for conflicting chord+scope combinations (fatal in debug, logged in release).
    public func detectConflicts() -> [(ShortcutBinding, ShortcutBinding)] {
        var seen: [String: ShortcutBinding] = [:]
        var conflicts: [(ShortcutBinding, ShortcutBinding)] = []
        for binding in bindings {
            let key = "\(binding.scope.rawValue):\(binding.keyChord.modifiers.sorted().joined()):\(binding.keyChord.key)"
            if let existing = seen[key] {
                conflicts.append((existing, binding))
            } else {
                seen[key] = binding
            }
        }
        return conflicts
    }

    public init(bindings: [ShortcutBinding]) {
        self.bindings = bindings
    }
}
