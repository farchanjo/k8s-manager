// Ports/Dependencies.swift — analytics_dashboard bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)
// ADR ref: ADR-0024 (Analytics Dashboard Bounded Context)

import Dependencies

// MARK: - ScopeRegistryPortKey

/// `DependencyKey` for `ScopeRegistryPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at composition root.
public enum ScopeRegistryPortKey: DependencyKey {
    public static let liveValue: any ScopeRegistryPort = UnimplementedScopeRegistryPort()
    public static let testValue: any ScopeRegistryPort = UnimplementedScopeRegistryPort()
}

public extension DependencyValues {
    /// The port that provides available dashboard scopes for a Kubernetes context.
    var scopeRegistry: any ScopeRegistryPort {
        get { self[ScopeRegistryPortKey.self] }
        set { self[ScopeRegistryPortKey.self] = newValue }
    }
}

// MARK: - MetricsQueryPortKey

/// `DependencyKey` for `MetricsQueryPort`.
public enum MetricsQueryPortKey: DependencyKey {
    public static let liveValue: any MetricsQueryPort = UnimplementedMetricsQueryPort()
    public static let testValue: any MetricsQueryPort = UnimplementedMetricsQueryPort()
}

public extension DependencyValues {
    /// The port that executes PromQL instant and range queries against `metrics_observability`.
    var analyticsMetricsQuery: any MetricsQueryPort {
        get { self[MetricsQueryPortKey.self] }
        set { self[MetricsQueryPortKey.self] = newValue }
    }
}

// MARK: - ResourceMetadataPortKey

/// `DependencyKey` for `ResourceMetadataPort`.
public enum ResourceMetadataPortKey: DependencyKey {
    public static let liveValue: any ResourceMetadataPort = UnimplementedResourceMetadataPort()
    public static let testValue: any ResourceMetadataPort = UnimplementedResourceMetadataPort()
}

public extension DependencyValues {
    /// The port that reads Kubernetes object state, conditions, and topology.
    var resourceMetadata: any ResourceMetadataPort {
        get { self[ResourceMetadataPortKey.self] }
        set { self[ResourceMetadataPortKey.self] = newValue }
    }
}

// MARK: - AuditTimelinePortKey

/// `DependencyKey` for `AuditTimelinePort`.
public enum AuditTimelinePortKey: DependencyKey {
    public static let liveValue: any AuditTimelinePort = UnimplementedAuditTimelinePort()
    public static let testValue: any AuditTimelinePort = UnimplementedAuditTimelinePort()
}

public extension DependencyValues {
    /// The port that provides cross-source audit timeline entries.
    var auditTimeline: any AuditTimelinePort {
        get { self[AuditTimelinePortKey.self] }
        set { self[AuditTimelinePortKey.self] = newValue }
    }
}

// MARK: - HelmReleaseTimelinePortKey

/// `DependencyKey` for `HelmReleaseTimelinePort`.
public enum HelmReleaseTimelinePortKey: DependencyKey {
    public static let liveValue: any HelmReleaseTimelinePort = UnimplementedHelmReleaseTimelinePort()
    public static let testValue: any HelmReleaseTimelinePort = UnimplementedHelmReleaseTimelinePort()
}

public extension DependencyValues {
    /// The port that provides Helm release history, manifest diffs, and hook outcomes.
    var helmReleaseTimeline: any HelmReleaseTimelinePort {
        get { self[HelmReleaseTimelinePortKey.self] }
        set { self[HelmReleaseTimelinePortKey.self] = newValue }
    }
}
