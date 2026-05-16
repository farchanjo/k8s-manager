// Ports/HelmReleaseTimelinePort.swift — analytics_dashboard bounded context
// DDD role: Port (outbound — consumes helm_management)
// Spec:      docs/arch/contexts/analytics_dashboard/domain/narrative.md §Ports
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Used by HelmReleaseDetail scope widgets: DiffViewer (revision manifests),
// EventTimeline (hook outcomes), and TopologyGraph (release → managed resource edges).

import Foundation

// MARK: - HelmRevisionSummary

/// Summary of a single Helm release revision.
public struct HelmRevisionSummary: Sendable, Codable, Hashable {
    /// Revision number (>= 1).
    public let revision: Int
    /// RFC 3339 timestamp when this revision was deployed.
    public let deployedAt: String
    /// Helm release status string (e.g., `"deployed"`, `"failed"`, `"superseded"`).
    public let status: String
    /// Helm chart version deployed in this revision.
    public let chartVersion: String
    /// Optional operator-provided description.
    public let description: String?

    /// Designated initialiser.
    public init(
        revision: Int,
        deployedAt: String,
        status: String,
        chartVersion: String,
        description: String? = nil
    ) {
        self.revision = revision
        self.deployedAt = deployedAt
        self.status = status
        self.chartVersion = chartVersion
        self.description = description
    }
}

// MARK: - HelmManifestDiff

/// A unified diff between two Helm release revision manifests.
public struct HelmManifestDiff: Sendable, Codable, Hashable {
    /// The older (left/baseline) revision number.
    public let leftRevision: Int
    /// The newer (right/current) revision number.
    public let rightRevision: Int
    /// Unified diff text in GNU diff format.
    public let unifiedDiff: String
    /// Set of resource kinds that changed between the two revisions.
    public let changedKinds: [String]

    /// Designated initialiser.
    public init(
        leftRevision: Int,
        rightRevision: Int,
        unifiedDiff: String,
        changedKinds: [String]
    ) {
        self.leftRevision = leftRevision
        self.rightRevision = rightRevision
        self.unifiedDiff = unifiedDiff
        self.changedKinds = changedKinds
    }
}

// MARK: - HelmHookOutcome

/// The outcome of a single Helm hook execution.
public struct HelmHookOutcome: Sendable, Codable, Hashable {
    /// Hook name (e.g., `"pre-install"`, `"post-upgrade"`).
    public let hookName: String
    /// Revision this hook was executed for.
    public let revision: Int
    /// RFC 3339 timestamp when the hook completed.
    public let completedAt: String
    /// `true` when the hook succeeded; `false` on failure or timeout.
    public let succeeded: Bool
    /// Hook pod logs on failure. `nil` when hook succeeded.
    public let failureLogs: String?

    /// Designated initialiser.
    public init(
        hookName: String,
        revision: Int,
        completedAt: String,
        succeeded: Bool,
        failureLogs: String? = nil
    ) {
        self.hookName = hookName
        self.revision = revision
        self.completedAt = completedAt
        self.succeeded = succeeded
        self.failureLogs = failureLogs
    }
}

// MARK: - HelmReleaseTimelinePort

/// Provides Helm release history, manifest diffs, and hook outcomes.
///
/// Consumes `helm_management`. Used by `HelmReleaseDetail` scope widgets:
/// - `DiffViewerWidget` — revision manifests.
/// - `EventTimelineWidget` — hook outcomes.
/// - `TopologyGraphWidget` — release → managed resource edges.
public protocol HelmReleaseTimelinePort: Sendable {
    /// Returns the revision history for the given Helm release.
    ///
    /// - Parameters:
    ///   - releaseName: The Helm release name.
    ///   - namespace: The namespace where the release is installed.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: Ordered list of revision summaries, newest first.
    /// - Throws: `HelmTimelineError` on connectivity or decode failure.
    func revisionHistory(
        releaseName: String,
        namespace: String,
        kubernetesContextId: String
    ) async throws -> [HelmRevisionSummary]

    /// Returns the unified diff between two revisions of a Helm release.
    ///
    /// - Parameters:
    ///   - releaseName: The Helm release name.
    ///   - namespace: The namespace where the release is installed.
    ///   - leftRevision: The older (baseline) revision number.
    ///   - rightRevision: The newer (current) revision number.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: A `HelmManifestDiff` with unified diff text.
    func manifestDiff(
        releaseName: String,
        namespace: String,
        leftRevision: Int,
        rightRevision: Int,
        kubernetesContextId: String
    ) async throws -> HelmManifestDiff

    /// Returns hook outcomes for the given release and revision.
    ///
    /// - Parameters:
    ///   - releaseName: The Helm release name.
    ///   - namespace: The namespace where the release is installed.
    ///   - revision: Specific revision to query hook outcomes for.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: List of hook outcomes, in execution order.
    func hookOutcomes(
        releaseName: String,
        namespace: String,
        revision: Int,
        kubernetesContextId: String
    ) async throws -> [HelmHookOutcome]
}

// MARK: - HelmTimelineError

/// Errors raised by `HelmReleaseTimelinePort` implementations.
public enum HelmTimelineError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// The specified Helm release does not exist.
    case releaseNotFound(name: String, namespace: String)
    /// The requested revision number does not exist for the release.
    case revisionNotFound(revision: Int)
    /// Connectivity failure when fetching from `helm_management`.
    case transportError(detail: String)
    /// Response could not be decoded.
    case decodeError(detail: String)
}

// MARK: - UnimplementedHelmReleaseTimelinePort

/// Crash-fast sentinel used as `liveValue` / `testValue` until an adapter registers.
public struct UnimplementedHelmReleaseTimelinePort: HelmReleaseTimelinePort {
    public init() {}

    public func revisionHistory(
        releaseName _: String,
        namespace _: String,
        kubernetesContextId _: String
    ) async throws -> [HelmRevisionSummary] {
        throw HelmTimelineError.unimplemented
    }

    public func manifestDiff(
        releaseName _: String,
        namespace _: String,
        leftRevision _: Int,
        rightRevision _: Int,
        kubernetesContextId _: String
    ) async throws -> HelmManifestDiff {
        throw HelmTimelineError.unimplemented
    }

    public func hookOutcomes(
        releaseName _: String,
        namespace _: String,
        revision _: Int,
        kubernetesContextId _: String
    ) async throws -> [HelmHookOutcome] {
        throw HelmTimelineError.unimplemented
    }
}
