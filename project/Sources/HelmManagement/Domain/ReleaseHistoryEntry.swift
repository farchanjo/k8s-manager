// Domain/ReleaseHistoryEntry.swift — helm_management bounded context
// DDD role: Entity + nested ValueObjects (ReleaseInfo, HookManifest)
// CUE source: docs/arch/contexts/helm_management/schemas/release_history_entry.cue
// ADR ref: ADR-0015

import Foundation

// MARK: - ReleaseHistoryEntry

/// Single row in the revision history of a Helm release.
///
/// Projected from a set of `Release` aggregates with the same (name, namespace)
/// identity. Carries only the fields needed for the history list view — it
/// omits the full manifest YAML and values to keep the read model payload small.
///
/// Identity: (kubernetesContextId, namespace, name, revision). Two entries with
/// the same identity represent the same Helm revision and must be deduplicated
/// by `ReleaseReaderActor`.
public struct ReleaseHistoryEntry: Hashable, Sendable, Codable {
    /// Helm revision number for this entry. Starts at 1.
    /// Matches the `version` field of the corresponding `Release` aggregate.
    public let revision: Int

    /// RFC3339 timestamp at which this revision was last deployed.
    /// Sourced from `info.lastDeployed` of the corresponding `Release`.
    public let deployedAtRFC3339: String

    /// Helm status for this revision at the time it was last written.
    public let status: ReleaseStatus

    /// Semantic version string of the chart used for this revision.
    /// Sourced from `chart.version` of the corresponding `Release`.
    public let chartVersion: String

    /// Application version from the chart. Optional for library charts.
    public let appVersion: String?

    /// Human-readable notes for this revision. Helm sets this to the chart's
    /// `NOTES.txt` output on install/upgrade, and to `"Rollback to <revision>"`
    /// on rollback operations.
    public let description: String

    /// RFC3339 timestamp at which this revision was superseded by a newer
    /// revision. Absent for the current (latest) revision.
    public let supersededAtRFC3339: String?

    public init(
        revision: Int,
        deployedAtRFC3339: String,
        status: ReleaseStatus,
        chartVersion: String,
        appVersion: String?,
        description: String,
        supersededAtRFC3339: String?
    ) {
        precondition(revision >= 1, "Helm revision numbers start at 1")
        self.revision = revision
        self.deployedAtRFC3339 = deployedAtRFC3339
        self.status = status
        self.chartVersion = chartVersion
        self.appVersion = appVersion
        self.description = description
        self.supersededAtRFC3339 = supersededAtRFC3339
    }
}

// MARK: - ReleaseInfo

/// Lifecycle timestamps and textual metadata for a single Helm release revision.
///
/// Corresponds to the `info` field in the Helm release JSON payload.
/// DDD role: ValueObject nested within `Release`.
public struct ReleaseInfo: Hashable, Sendable, Codable {
    /// RFC3339 timestamp of the first successful installation of this release
    /// (revision 1). Sourced from `info.first_deployed`.
    public let firstDeployed: String

    /// RFC3339 timestamp of the most recent successful deployment of this
    /// revision. Sourced from `info.last_deployed`.
    public let lastDeployed: String

    /// RFC3339 timestamp at which the release was uninstalled.
    /// Present only for revisions with status `uninstalled`.
    public let deleted: String?

    /// Human-readable status description. On install/upgrade this is the
    /// rendered `NOTES.txt`. On rollback: `"Rollback to <target revision>"`.
    /// On uninstall: `"Uninstallation complete"`.
    public let description: String

    /// Status mirrors the release status at the time this info was written.
    public let status: ReleaseStatus

    /// Raw `NOTES.txt` content rendered for this revision.
    /// Empty string when the chart has no `NOTES.txt` template.
    public let notes: String

    public init(
        firstDeployed: String,
        lastDeployed: String,
        deleted: String?,
        description: String,
        status: ReleaseStatus,
        notes: String
    ) {
        self.firstDeployed = firstDeployed
        self.lastDeployed = lastDeployed
        self.deleted = deleted
        self.description = description
        self.status = status
        self.notes = notes
    }
}

// MARK: - HookManifest

/// Single Helm hook declared by the chart.
///
/// Hooks are Kubernetes resources that Helm applies at specific lifecycle
/// events rather than as part of normal resource reconciliation.
///
/// Phase 1: read-only. K8sManager displays declared hooks and their metadata
/// but does not invoke or re-apply them.
///
/// DDD role: ValueObject nested within `Release`.
public struct HookManifest: Hashable, Sendable, Codable {
    /// Hook's name, derived from the resource `metadata.name`.
    public let name: String

    /// Kubernetes resource kind. Examples: `"Job"`, `"Pod"`, `"ServiceAccount"`.
    public let kind: String

    /// API version string of the hook resource. Examples: `"batch/v1"`, `"v1"`.
    public let apiVersion: String

    /// Helm lifecycle events that trigger this hook. At least one event
    /// must be present.
    public let events: [HookEvent]

    /// Delete-policy annotations governing when Helm removes the hook
    /// resource after it completes.
    /// Common values: `"before-hook-creation"`, `"hook-succeeded"`,
    /// `"hook-failed"`.
    public let deletePolicy: [String]

    /// Execution weight. Hooks are executed in ascending order of weight.
    /// Negative weights are permitted.
    public let weight: Int

    public init(
        name: String,
        kind: String,
        apiVersion: String,
        events: [HookEvent],
        deletePolicy: [String],
        weight: Int
    ) {
        self.name = name
        self.kind = kind
        self.apiVersion = apiVersion
        self.events = events
        self.deletePolicy = deletePolicy
        self.weight = weight
    }
}

// MARK: - HookEvent

/// Helm lifecycle event that can trigger a hook.
public enum HookEvent: String, Hashable, Sendable, Codable, CaseIterable {
    case preInstall = "pre-install"
    case postInstall = "post-install"
    case preUpgrade = "pre-upgrade"
    case postUpgrade = "post-upgrade"
    case preDelete = "pre-delete"
    case postDelete = "post-delete"
    case preRollback = "pre-rollback"
    case postRollback = "post-rollback"
    case test
}
