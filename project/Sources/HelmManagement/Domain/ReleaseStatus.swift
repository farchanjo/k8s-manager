// Domain/ReleaseStatus.swift — helm_management bounded context
// DDD role: Enumeration (shared by Release, ReleaseHistoryEntry, ReleaseInfo)
// CUE source: docs/arch/contexts/helm_management/schemas/release.cue §status
// ADR ref: ADR-0015 §Phase 1 §Status mapping

import Foundation

// MARK: - ReleaseStatus

/// Helm release lifecycle status mirroring the `release.Status` Go type.
///
/// Maps the closed set of status strings stored in the
/// `helm.sh/release.v1` Secret JSON payload. All seven values from
/// Helm 3's `release.Status` type are represented.
public enum ReleaseStatus: String, Hashable, Sendable, Codable, CaseIterable {
    /// The release was successfully applied to the cluster.
    case deployed = "deployed"

    /// All release resources were deleted via `helm uninstall`.
    case uninstalled = "uninstalled"

    /// An older revision that has been replaced by a newer one.
    case superseded = "superseded"

    /// The install or upgrade did not complete successfully.
    case failed = "failed"

    /// An install operation is currently in progress.
    case pendingInstall = "pending-install"

    /// An upgrade operation is currently in progress.
    case pendingUpgrade = "pending-upgrade"

    /// A rollback operation is currently in progress.
    case pendingRollback = "pending-rollback"

    /// Returns `true` when the revision represents a terminal success state
    /// (deployed or uninstalled). Convenience for list-view filtering.
    public var isTerminal: Bool {
        switch self {
        case .deployed, .uninstalled, .superseded, .failed: true
        case .pendingInstall, .pendingUpgrade, .pendingRollback: false
        }
    }

    /// Returns `true` when the revision is the current live state
    /// (not superseded or in-progress).
    public var isCurrent: Bool {
        switch self {
        case .deployed, .failed, .uninstalled: true
        case .superseded, .pendingInstall, .pendingUpgrade, .pendingRollback: false
        }
    }
}
