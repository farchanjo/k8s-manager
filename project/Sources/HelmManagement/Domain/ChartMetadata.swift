// Domain/ChartMetadata.swift — helm_management bounded context
// DDD role: ValueObject (nested within Release aggregate root)
// CUE source: docs/arch/contexts/helm_management/schemas/chart_metadata.cue
// ADR ref: ADR-0015

import Foundation

// MARK: - ChartMetadata

/// Immutable description of the Helm chart used to render a release revision.
///
/// Decoded from the `chart.metadata` field of the Helm release JSON embedded
/// in the `helm.sh/release.v1` Secret. Corresponds to the `chart.Metadata`
/// Go struct in `helm/helm`.
///
/// Equality is structural: two values are equal when every populated field
/// matches. The practical identity for display and grouping is (name, version).
public struct ChartMetadata: Hashable, Sendable, Codable {
    /// Chart name as declared in `Chart.yaml`.
    ///
    /// Lowercase alphanumeric with hyphens. Examples: "nginx", "cert-manager".
    public let name: String

    /// Chart version string conforming to SemVer 2.0.0.
    ///
    /// Example: "1.2.3", "0.14.0-rc.1".
    public let version: String

    /// Version of the application the chart installs. Optional for library charts.
    public let appVersion: String?

    /// Chart.yaml schema version. `"v1"` for Helm 2; `"v2"` for Helm 3.
    public let apiVersion: ChartAPIVersion

    /// Human-readable chart description from `Chart.yaml`.
    public let description: String?

    /// Whether the chart is an application chart or a library chart.
    public let type: ChartType?

    /// URL of an icon image for Helm Hub or chart museum UIs.
    public let icon: String?

    /// Sub-charts this chart depends on.
    public let dependencies: [ChartDependency]

    /// Maintainers declared in `Chart.yaml`.
    public let maintainers: [Maintainer]

    /// URL of the chart's home page.
    public let home: String?

    /// Source code URLs associated with the chart.
    public let sources: [String]

    public init(
        name: String,
        version: String,
        appVersion: String?,
        apiVersion: ChartAPIVersion,
        description: String?,
        type: ChartType?,
        icon: String?,
        dependencies: [ChartDependency],
        maintainers: [Maintainer],
        home: String?,
        sources: [String]
    ) {
        self.name = name
        self.version = version
        self.appVersion = appVersion
        self.apiVersion = apiVersion
        self.description = description
        self.type = type
        self.icon = icon
        self.dependencies = dependencies
        self.maintainers = maintainers
        self.home = home
        self.sources = sources
    }
}

// MARK: - ChartAPIVersion

/// Chart.yaml schema version discriminant.
public enum ChartAPIVersion: String, Hashable, Sendable, Codable {
    /// Helm 2 chart schema.
    case v1
    /// Helm 3 chart schema.
    case v2
}

// MARK: - ChartType

/// Distinguishes application charts from library charts.
public enum ChartType: String, Hashable, Sendable, Codable {
    /// A chart that can be installed and creates release resources.
    case application
    /// A chart that provides reusable helpers; cannot be installed directly.
    case library
}

// MARK: - ChartDependency

/// A single dependency entry from a chart's `Chart.yaml` dependencies list.
///
/// Read-only in Phase 1: decoded from embedded chart metadata but never resolved
/// or pulled by K8sManager.
public struct ChartDependency: Hashable, Sendable, Codable {
    /// Dependency chart name.
    public let name: String

    /// SemVer constraint string. Examples: ">=1.2.3", "~1.0", "1.x".
    public let version: String

    /// Repository URL or OCI reference. Optional for bundled sub-charts.
    public let repository: String?

    /// Alternative name to give the chart in the parent chart's template context.
    public let alias: String?

    /// Dotpath into the parent chart's values to conditionally disable this dependency.
    public let condition: String?

    /// Tags for conditional enabling or disabling of dependency groups.
    public let tags: [String]

    public init(
        name: String,
        version: String,
        repository: String?,
        alias: String?,
        condition: String?,
        tags: [String]
    ) {
        self.name = name
        self.version = version
        self.repository = repository
        self.alias = alias
        self.condition = condition
        self.tags = tags
    }
}

// MARK: - Maintainer

/// A single maintainer entry from `Chart.yaml`.
public struct Maintainer: Hashable, Sendable, Codable {
    /// Maintainer's display name.
    public let name: String

    /// Maintainer's email address.
    public let email: String?

    /// Maintainer's web URL.
    public let url: String?

    public init(name: String, email: String?, url: String?) {
        self.name = name
        self.email = email
        self.url = url
    }
}
