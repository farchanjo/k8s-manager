// Ports/Dependencies.swift — metrics_observability bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies

// MARK: - PrometheusQueryPortKey

/// `DependencyKey` for `PrometheusQueryPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at composition root.
public enum PrometheusQueryPortKey: DependencyKey {
    public static let liveValue: any PrometheusQueryPort = UnimplementedPrometheusQueryPort()
    public static let testValue: any PrometheusQueryPort = UnimplementedPrometheusQueryPort()
}

public extension DependencyValues {
    /// The port that executes PromQL instant and range queries.
    var prometheusQuery: any PrometheusQueryPort {
        get { self[PrometheusQueryPortKey.self] }
        set { self[PrometheusQueryPortKey.self] = newValue }
    }
}

// MARK: - EndpointDiscoveryPortKey

/// `DependencyKey` for `EndpointDiscoveryPort`.
public enum EndpointDiscoveryPortKey: DependencyKey {
    public static let liveValue: any EndpointDiscoveryPort = UnimplementedEndpointDiscoveryPort()
    public static let testValue: any EndpointDiscoveryPort = UnimplementedEndpointDiscoveryPort()
}

public extension DependencyValues {
    /// The port that auto-discovers Prometheus endpoints via the Kubernetes API.
    var endpointDiscovery: any EndpointDiscoveryPort {
        get { self[EndpointDiscoveryPortKey.self] }
        set { self[EndpointDiscoveryPortKey.self] = newValue }
    }
}
