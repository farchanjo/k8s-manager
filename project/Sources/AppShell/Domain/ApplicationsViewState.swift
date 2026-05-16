// Domain/ApplicationsViewState.swift — app_shell bounded context
// DDD role: Value object — read model for the Applications cluster-scope view
// ADR ref: ADR-0067 (applications cluster-scope view — Helm releases + GitOps extension hooks)
// CUE source: docs/arch/contexts/resource_browser/schemas/applications_view_state.cue

import Foundation
import HelmManagement
import SharedKernel

// MARK: - ApplicationSortOrder

/// Column-sort axis for ``ApplicationsViewState/releases``.
public enum ApplicationSortOrder: Hashable, Sendable {
    /// Sort by release name, ascending.
    case nameAscending
    /// Sort by release name, descending.
    case nameDescending
    /// Sort by chart name, ascending.
    case chartAscending
    /// Sort by chart name, descending.
    case chartDescending
    /// Sort by namespace, ascending.
    case namespaceAscending
    /// Sort by most-recently updated (descending by default).
    case updatedDescending
}

// MARK: - ApplicationRow

/// Flat read-model row for a single Helm release in the Applications view.
///
/// Maps directly to the seven columns specified in ADR-0067 §ApplicationsView data source.
/// Superseded revisions are excluded at construction time; this struct always
/// represents the current, non-superseded state of a release.
public struct ApplicationRow: Identifiable, Hashable, Sendable {
    /// Stable identifier reusing the underlying ``Release`` UUID.
    public let id: UUID
    /// Helm release name.
    public let name: String
    /// Chart name without repository prefix (e.g. `"nginx-ingress"`).
    public let chartName: String
    /// Chart version string (e.g. `"4.10.0"`).
    public let chartVersion: String
    /// Helm release lifecycle status.
    public let status: ReleaseStatus
    /// Relative description of last deployment (e.g. `"3 days ago"`).
    ///
    /// Derived from the RFC 3339 `last_deployed` timestamp relative to
    /// the supplied reference date at construction time.
    public let updatedRelative: String
    /// Kubernetes namespace where the release is installed.
    public let namespace: String
    /// Current revision integer.
    public let revision: Int

    /// Stable sort key for the `updatedRelative` column (raw RFC3339 string).
    ///
    /// Not displayed in the UI; used only for sort comparisons.
    public let updatedRFC3339: String

    public init(
        id: UUID,
        name: String,
        chartName: String,
        chartVersion: String,
        status: ReleaseStatus,
        updatedRelative: String,
        updatedRFC3339: String,
        namespace: String,
        revision: Int
    ) {
        self.id = id
        self.name = name
        self.chartName = chartName
        self.chartVersion = chartVersion
        self.status = status
        self.updatedRelative = updatedRelative
        self.updatedRFC3339 = updatedRFC3339
        self.namespace = namespace
        self.revision = revision
    }
}

// MARK: - ApplicationsViewState

/// Aggregated read model for the Applications cluster-scope view.
///
/// Carries Helm releases projected from the ``HelmManagement`` actor read model,
/// plus extension-hook flags for future GitOps tool integration (ADR-0067
/// §"Deferred extension contract").
///
/// All mutations happen in ``ApplicationsViewModel`` on `@MainActor`; this
/// struct is a plain value object and carries no business logic.
public struct ApplicationsViewState: Sendable {

    // MARK: - Properties

    /// Filtered, sorted list of Helm release rows ready for display.
    public var releases: [ApplicationRow]

    /// Active namespace filter; `nil` means all namespaces.
    public var namespaceFilter: String?

    /// Current sort order applied to `releases`.
    public var sortOrder: ApplicationSortOrder

    /// Whether an ArgoCD Application source is available (ADR-0067 extension hook).
    ///
    /// Always `false` in v1; reserved for the follow-up ArgoCD ADR.
    public let argocdEnabled: Bool

    /// Whether a Flux Kustomization source is available (ADR-0067 extension hook).
    ///
    /// Always `false` in v1; reserved for the follow-up Flux ADR.
    public let fluxEnabled: Bool

    // MARK: - Init

    public init(
        releases: [ApplicationRow] = [],
        namespaceFilter: String? = nil,
        sortOrder: ApplicationSortOrder = .nameAscending,
        argocdEnabled: Bool = false,
        fluxEnabled: Bool = false
    ) {
        self.releases = releases
        self.namespaceFilter = namespaceFilter
        self.sortOrder = sortOrder
        self.argocdEnabled = argocdEnabled
        self.fluxEnabled = fluxEnabled
    }

    /// Sentinel empty state used before the first data load.
    public static let empty = ApplicationsViewState()
}

// MARK: - ApplicationRow + Release projection

extension ApplicationRow {

    /// Projects a ``Release`` aggregate into a flat `ApplicationRow`.
    ///
    /// - Parameters:
    ///   - release: The Helm release aggregate to project.
    ///   - referenceDate: The date used for computing the relative `updatedRelative` string.
    ///     Defaults to `Date.now`; pass a fixed date in tests.
    public init(from release: Release, referenceDate: Date = .now) {
        self.id = release.id
        self.name = release.name
        // Strip repository prefix — take only the last path component.
        let rawChart = release.chart.name
        self.chartName = rawChart.components(separatedBy: "/").last ?? rawChart
        self.chartVersion = release.chart.version
        self.status = release.status
        self.updatedRFC3339 = release.modifiedAtRFC3339
        self.updatedRelative = Self.relativeString(
            from: release.modifiedAtRFC3339,
            referenceDate: referenceDate
        )
        self.namespace = release.namespace
        self.revision = release.version
    }

    // MARK: Private helpers

    private static func relativeString(from rfc3339: String, referenceDate: Date) -> String {
        guard let date = ISO8601DateFormatter().date(from: rfc3339) else { return rfc3339 }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date,
            to: referenceDate
        )
        if let years = components.year, years > 0 {
            return years == 1 ? "1 year ago" : "\(years) years ago"
        }
        if let months = components.month, months > 0 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
        if let days = components.day, days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
        if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }
        if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }
        return "just now"
    }
}
