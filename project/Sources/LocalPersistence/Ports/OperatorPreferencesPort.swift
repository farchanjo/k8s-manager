// Ports/OperatorPreferencesPort.swift — local_persistence bounded context
// DDD role: Port (secondary — outbound to persistence infrastructure)
// Consumed by: app_shell bounded context
// Narrative ref: domain/narrative.md §Tactical roles
// ADR refs: ADR-0010 (storage design), ADR-0026 (filesystem layout)
//
// `OperatorPreferences` stores per-operator UX configuration that is persisted
// in `storage.sqlite3` under the `operator_preferences` key-value table.
// The port is consumed by `app_shell` on cold launch to restore theme, locale,
// layout, and recent-resource state.

import Foundation

// MARK: - AppTheme

/// Visual theme selection for the application shell.
public enum AppTheme: String, Hashable, Sendable, Codable {
    /// Follow the system appearance setting (default).
    case system
    /// Force light appearance.
    case light
    /// Force dark appearance.
    case dark
}

// MARK: - AppLocale

/// Locale override for the application shell.
///
/// `nil` in `OperatorPreferences` means "follow system locale".
/// When non-nil, the value is a BCP 47 language tag (e.g. `"en-US"`, `"pt-BR"`).
public struct AppLocale: Hashable, Sendable, Codable {
    /// BCP 47 language tag.
    ///
    /// Invariant: non-empty.
    public let bcp47: String

    public init(bcp47: String) {
        self.bcp47 = bcp47
    }

    /// Returns `true` when the tag is non-empty.
    public var isValid: Bool { !bcp47.isEmpty }
}

// MARK: - SidebarLayout

/// Sidebar display preference.
public enum SidebarLayout: String, Hashable, Sendable, Codable {
    /// Always show the sidebar (default).
    case visible
    /// Auto-collapse the sidebar when the main content area is narrow.
    case autoCollapse = "auto_collapse"
    /// Always hide the sidebar (accessible via keyboard shortcut only).
    case hidden
}

// MARK: - RecentResource

/// A recently accessed Kubernetes resource entry stored in preferences.
public struct RecentResource: Hashable, Sendable, Codable {
    /// UUIDv7 of the cluster context this resource belongs to.
    public let clusterId: UUID
    /// Kubernetes API group/version/kind, e.g. `"apps/v1/Deployment"`.
    public let gvk: String
    /// Namespace the resource resides in. `nil` for cluster-scoped resources.
    public let namespace: String?
    /// Resource name as returned by the API server.
    public let name: String
    /// Timestamp of the most recent access.
    public let lastAccessedAt: Date

    public init(
        clusterId: UUID,
        gvk: String,
        namespace: String?,
        name: String,
        lastAccessedAt: Date
    ) {
        self.clusterId = clusterId
        self.gvk = gvk
        self.namespace = namespace
        self.name = name
        self.lastAccessedAt = lastAccessedAt
    }

    private enum CodingKeys: String, CodingKey {
        case clusterId       = "cluster_id"
        case gvk
        case namespace
        case name
        case lastAccessedAt  = "last_accessed_at"
    }
}

// MARK: - OperatorPreferences

/// Per-operator UX configuration persisted in `storage.sqlite3`.
///
/// Loaded on cold launch by `app_shell` via `OperatorPreferencesPort`.
/// All fields have sensible defaults so fresh-install users receive a working
/// configuration without any prior write.
public struct OperatorPreferences: Hashable, Sendable, Codable {

    /// Visual theme selection. Defaults to `.system`.
    public let theme: AppTheme

    /// Locale override. `nil` means follow the system locale.
    public let locale: AppLocale?

    /// Sidebar layout preference. Defaults to `.visible`.
    public let sidebarLayout: SidebarLayout

    /// Ordered list of recently accessed resources (most recent first).
    /// Capped at 50 entries by the adapter.
    public let recentResources: [RecentResource]

    public init(
        theme: AppTheme = .system,
        locale: AppLocale? = nil,
        sidebarLayout: SidebarLayout = .visible,
        recentResources: [RecentResource] = []
    ) {
        self.theme = theme
        self.locale = locale
        self.sidebarLayout = sidebarLayout
        self.recentResources = recentResources
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case locale
        case sidebarLayout    = "sidebar_layout"
        case recentResources  = "recent_resources"
    }
}

// MARK: - OperatorPreferencesError

/// Errors raised by `OperatorPreferencesPort` implementations.
public enum OperatorPreferencesError: Error, Sendable {
    /// The underlying persistence layer returned an error.
    case storageError(underlying: String)
    /// The port has not been registered in this process.
    case unimplemented
}

// MARK: - OperatorPreferencesPort

/// Port for loading and saving the operator's UX preferences.
///
/// Declared in the domain core; implemented by the `GRDBPersistenceAdapter`
/// target. Consumed by `app_shell`. The domain core never imports GRDB.
public protocol OperatorPreferencesPort: Sendable {
    /// Loads the current operator preferences from persistent storage.
    ///
    /// Returns a default `OperatorPreferences()` on fresh install (when no
    /// record exists yet).
    ///
    /// - Throws: `OperatorPreferencesError.storageError` on persistence
    ///   failure.
    func loadPreferences() async throws -> OperatorPreferences

    /// Persists `preferences` to the underlying storage.
    ///
    /// Overwrites any previously stored value atomically.
    ///
    /// - Throws: `OperatorPreferencesError.storageError` on persistence
    ///   failure.
    func savePreferences(_ preferences: OperatorPreferences) async throws
}

// MARK: - UnimplementedOperatorPreferencesPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedOperatorPreferencesPort: OperatorPreferencesPort {
    public init() {}

    public func loadPreferences() async throws -> OperatorPreferences {
        throw OperatorPreferencesError.unimplemented
    }

    public func savePreferences(_ preferences: OperatorPreferences) async throws {
        throw OperatorPreferencesError.unimplemented
    }
}
