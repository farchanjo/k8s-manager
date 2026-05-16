// Domain/StateRestoration.swift — local_persistence bounded context
// DDD role: ValueObject (cold-launch restoration manifest aggregate)
// CUE source: docs/arch/contexts/local_persistence/schemas/state_restoration.cue
// ADR refs: ADR-0026 (state persistence and filesystem layout)
//
// These value objects are assembled once during cold launch by `PersistenceActor`
// from storage.sqlite3 and per-cluster JSON files, handed to the application
// bootstrap sequence, then discarded. They are NOT persisted as whole documents.
//
// Mirror rules (enforced by CUE lint):
//   • All field names snake_case in CUE → camelCase in Swift via CodingKeys.
//   • Optional fields (CUE `?:`) → Swift `Optional`.
//   • Array defaults (`| *[]`) → non-optional arrays (default `[]` in init).

import Foundation

// MARK: - RestorationPromptKind

/// Discriminator for operator-facing confirmation dialogs shown during
/// cold-launch restoration.
///
/// Mirrors `#RestorationPromptKind` from `state_restoration.cue`.
public enum RestorationPromptKind: String, Hashable, Sendable, Codable {
    /// Asks the operator whether to reopen terminal sessions from the previous
    /// application run.
    case reopenTerminals = "reopen_terminals"

    /// Asks the operator whether to reopen port-forward listeners from the
    /// previous application run.
    case reopenPortForwards = "reopen_port_forwards"

    /// Asks the operator whether to migrate the legacy `storage.sqlite3` from
    /// `~/Library/Application Support/com.archanjo.K8sManager/` to
    /// `~/.config/k8smanager/` (ADR-0026 first-run migration).
    case migrateStoragePath = "migrate_storage_path"
}

// MARK: - RestorationPrompt

/// A single operator-facing confirmation dialog presented during cold launch.
///
/// Each prompt is persisted to `storage.sqlite3` after the operator responds,
/// providing an audit trail of restoration decisions.
///
/// Mirrors `#RestorationPrompt` from `state_restoration.cue`.
public struct RestorationPrompt: Hashable, Sendable, Codable {

    /// Category of confirmation being requested.
    public let kind: RestorationPromptKind

    /// Opaque JSON string carrying kind-specific supplementary data needed to
    /// render the prompt.
    ///
    /// - `"reopen_terminals"`: `{"count": N, "sessionIds": [...]}`
    /// - `"reopen_port_forwards"`: `{"count": M, "forwardIds": [...]}`
    /// - `"migrate_storage_path"`: `{"sourcePath": "...", "targetPath": "..."}`
    ///
    /// Invariant: must be non-empty (CUE `string & !=""`).
    public let payload: String

    /// Whether the operator confirmed (`true`) or declined (`false`) the prompt.
    /// Set after operator interaction.
    public let accepted: Bool

    /// RFC 3339 timestamp when the prompt was displayed to the operator.
    public let presentedAt: Date

    public init(
        kind: RestorationPromptKind,
        payload: String,
        accepted: Bool,
        presentedAt: Date
    ) {
        self.kind = kind
        self.payload = payload
        self.accepted = accepted
        self.presentedAt = presentedAt
    }

    /// Returns `true` when all CUE-declared invariants hold.
    public var isValid: Bool {
        !payload.isEmpty
    }

    // MARK: CodingKeys

    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
        case accepted
        case presentedAt = "presented_at"
    }
}

// MARK: - RestorationManifest

/// Declarative list of resources to restore during cold launch.
///
/// Assembled once by `PersistenceActor` from `storage.sqlite3` and
/// per-cluster JSON files. Handed off to the application bootstrap sequence
/// and then discarded — it is never persisted as a whole document.
///
/// Mirrors `#RestorationManifest` from `state_restoration.cue`.
public struct RestorationManifest: Hashable, Sendable, Codable {

    /// Version of this manifest format.
    ///
    /// Increment when fields are added or removed so that the bootstrap code
    /// can handle forward and backward compatibility.
    /// Invariant: `>= 1`.
    public let schemaVersion: Int

    /// RFC 3339 timestamp recorded when the application last performed a
    /// graceful shutdown.
    ///
    /// `nil` on fresh install or after a crash.
    public let lastClosedAt: Date?

    /// UUIDv7 of the `ContextNavigationState` context that was active when
    /// the application last closed. `nil` on fresh install.
    public let activeContextId: UUID?

    /// Terminal-session UUIDv7 identifiers that were open at last shutdown.
    ///
    /// If non-empty, the bootstrap sequence emits a
    /// `.reopenTerminals` `RestorationPrompt`.
    public let openTerminalSessions: [UUID]

    /// Port-forward UUIDv7 identifiers that were active at last shutdown.
    ///
    /// If non-empty, the bootstrap sequence emits a
    /// `.reopenPortForwards` `RestorationPrompt`.
    public let openPortForwards: [UUID]

    /// Ordered list of cluster context UUIDv7 identifiers pinned in the
    /// sidebar. These sessions are spawned unconditionally on cold launch.
    public let pinnedClusterContextIds: [UUID]

    /// Chat-session UUIDv7 identifiers that were open at last shutdown.
    /// Restored in the order listed without prompting.
    public let chatSessions: [UUID]

    /// Map from layout scope identifier (cluster context UUIDv7 or
    /// `"global"`) to an opaque JSON string encoding the operator's
    /// dashboard layout override for that scope.
    ///
    /// The schema of the layout JSON is owned by the `analytics_dashboard`
    /// bounded context; `local_persistence` stores it without interpreting it.
    public let dashboardCustomLayouts: [String: String]

    public init(
        schemaVersion: Int,
        lastClosedAt: Date? = nil,
        activeContextId: UUID? = nil,
        openTerminalSessions: [UUID] = [],
        openPortForwards: [UUID] = [],
        pinnedClusterContextIds: [UUID] = [],
        chatSessions: [UUID] = [],
        dashboardCustomLayouts: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.lastClosedAt = lastClosedAt
        self.activeContextId = activeContextId
        self.openTerminalSessions = openTerminalSessions
        self.openPortForwards = openPortForwards
        self.pinnedClusterContextIds = pinnedClusterContextIds
        self.chatSessions = chatSessions
        self.dashboardCustomLayouts = dashboardCustomLayouts
    }

    /// Returns `true` when all CUE-declared invariants hold.
    public var isValid: Bool {
        schemaVersion >= 1
    }

    // MARK: CodingKeys

    private enum CodingKeys: String, CodingKey {
        case schemaVersion          = "schema_version"
        case lastClosedAt           = "last_closed_at"
        case activeContextId        = "active_context_id"
        case openTerminalSessions   = "open_terminal_sessions"
        case openPortForwards       = "open_port_forwards"
        case pinnedClusterContextIds = "pinned_cluster_context_ids"
        case chatSessions           = "chat_sessions"
        case dashboardCustomLayouts = "dashboard_custom_layouts"
    }
}

// MARK: - StateRestoration

/// Aggregate combining a `RestorationManifest` with any `RestorationPrompt`
/// instances generated during the cold-launch bootstrap sequence.
///
/// The application bootstrap uses this aggregate as the single handoff
/// object between `PersistenceActor` and the top-level entry point.
public struct StateRestoration: Hashable, Sendable, Codable {

    /// The declarative manifest assembled from persistent storage.
    public let manifest: RestorationManifest

    /// Prompts that the bootstrap sequence must present to the operator
    /// before completing restoration. May be empty.
    public let pendingPrompts: [RestorationPrompt]

    public init(
        manifest: RestorationManifest,
        pendingPrompts: [RestorationPrompt] = []
    ) {
        self.manifest = manifest
        self.pendingPrompts = pendingPrompts
    }

    /// Returns `true` when the manifest is valid and all pending prompts
    /// satisfy their own invariants.
    public var isValid: Bool {
        manifest.isValid && pendingPrompts.allSatisfy(\.isValid)
    }

    // MARK: CodingKeys

    private enum CodingKeys: String, CodingKey {
        case manifest
        case pendingPrompts = "pending_prompts"
    }
}
