// Domain/ClusterOperations.swift — app_shell bounded context
// DDD role: ValueObjects — API resource discovery + apply pipeline domain types
// ADR ref: ADR-0050 (cluster operations category, Onda 2)

import Foundation

// MARK: - APIResource

/// Describes a single Kubernetes API resource type as returned by the discovery API.
///
/// Aggregated across all server groups via `serverResourcesForGroupVersion()`.
/// Used to populate the API Resources browser table.
public struct APIResource: Identifiable, Sendable, Hashable {

    /// Stable composite identifier: `"group/version/kind"`.
    public let id: String

    /// API group (e.g. `"apps"`, `"batch"`) or `""` for the core group.
    public let group: String

    /// API version string (e.g. `"v1"`, `"v1beta1"`).
    public let version: String

    /// Kind name (e.g. `"Pod"`, `"Deployment"`).
    public let kind: String

    /// Plural REST endpoint name (e.g. `"pods"`, `"deployments"`).
    public let plural: String

    /// Optional short-form names (e.g. `["po"]` for Pods, `["svc"]` for Services).
    public let shortNames: [String]

    /// Whether this resource is scoped to a namespace.
    public let isNamespaced: Bool

    /// Verbs supported by the API server for this resource.
    /// Common values: `"get"`, `"list"`, `"watch"`, `"create"`, `"update"`, `"patch"`, `"delete"`.
    public let verbs: [String]

    /// Memberwise initialiser.
    public init(
        group: String,
        version: String,
        kind: String,
        plural: String,
        shortNames: [String] = [],
        isNamespaced: Bool,
        verbs: [String] = []
    ) {
        self.group = group
        self.version = version
        self.kind = kind
        self.plural = plural
        self.shortNames = shortNames
        self.isNamespaced = isNamespaced
        self.verbs = verbs
        self.id = "\(group)/\(version)/\(kind)"
    }

    /// Returns `true` when any of `kind`, `plural`, or `shortNames` contain `query` (case-insensitive).
    public func matches(query: String) -> Bool {
        let q = query.lowercased()
        if kind.lowercased().contains(q) { return true }
        if plural.lowercased().contains(q) { return true }
        if group.lowercased().contains(q) { return true }
        return shortNames.contains { $0.lowercased().contains(q) }
    }
}

// MARK: - ApplyResult

/// Outcome of a server-side apply (SSA) operation.
///
/// Returned by `ApplyYAMLViewModel.apply(clusterId:)` on success.
public struct ApplyResult: Sendable {

    /// References to every resource successfully applied in this operation.
    public let appliedResources: [ResourceRef]

    /// `true` when the operation was a dry-run (no persistent state change).
    public let dryRun: Bool

    /// Serialised managed-fields diff returned by the API server for dry-run preview.
    /// `nil` when `dryRun == false`.
    public let managedFieldsDiff: String?

    /// Memberwise initialiser.
    public init(
        appliedResources: [ResourceRef],
        dryRun: Bool,
        managedFieldsDiff: String? = nil
    ) {
        self.appliedResources = appliedResources
        self.dryRun = dryRun
        self.managedFieldsDiff = managedFieldsDiff
    }
}

// MARK: - ValidationError

/// A single inline validation diagnostic for YAML/JSON apply editor content.
///
/// Produced by `ApplyYAMLViewModel.validate()` and displayed in the editor gutter
/// or an inline error panel.
public struct ValidationError: Sendable, Identifiable {

    /// Severity level that controls icon and colour used in the UI.
    public enum Severity: Sendable {
        /// Prevents the apply operation from proceeding.
        case error
        /// Advisory; apply can still proceed.
        case warning
    }

    /// Stable unique identifier for use with SwiftUI `ForEach`.
    public let id: UUID

    /// 1-based line number in the editor where the issue was detected.
    public let line: Int

    /// 1-based column offset, or `nil` when only line precision is available.
    public let column: Int?

    /// Human-readable description of the problem.
    public let message: String

    /// Whether this diagnostic blocks the apply operation.
    public let severity: Severity

    /// Memberwise initialiser.
    public init(
        id: UUID = UUID(),
        line: Int,
        column: Int? = nil,
        message: String,
        severity: Severity
    ) {
        self.id = id
        self.line = line
        self.column = column
        self.message = message
        self.severity = severity
    }
}

// MARK: - DiagnosticsCollectionState

/// Describes the current phase of a diagnostics bundle collection run.
public enum DiagnosticsCollectionState: Sendable {
    /// No collection in progress.
    case idle
    /// Collection is running; carries a human-readable status line.
    case collecting(status: String)
    /// Collection completed; bundle is available at `bundleURL`.
    case done(bundleURL: URL)
    /// Collection aborted with an error.
    case failed(Error)
}
