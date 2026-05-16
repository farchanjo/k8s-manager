// Ports/Dependencies.swift — helm_management bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
import SharedKernel

// MARK: - HelmReleaseStorePortKey

/// `DependencyKey` for `HelmReleaseStorePort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at composition root.
public enum HelmReleaseStorePortKey: DependencyKey {
    public static let liveValue: any HelmReleaseStorePort = UnimplementedHelmReleaseStorePort()
    public static let testValue: any HelmReleaseStorePort = UnimplementedHelmReleaseStorePort()
}

public extension DependencyValues {
    /// The port responsible for reading and writing Helm release Secrets.
    var helmReleaseStore: any HelmReleaseStorePort {
        get { self[HelmReleaseStorePortKey.self] }
        set { self[HelmReleaseStorePortKey.self] = newValue }
    }
}

// MARK: - ServerSideApplyPortKey

/// `DependencyKey` for `ServerSideApplyPort`.
public enum ServerSideApplyPortKey: DependencyKey {
    public static let liveValue: any ServerSideApplyPort = UnimplementedServerSideApplyPort()
    public static let testValue: any ServerSideApplyPort = UnimplementedServerSideApplyPort()
}

public extension DependencyValues {
    /// The port that issues Server-Side Apply PATCH requests for rollback.
    var serverSideApply: any ServerSideApplyPort {
        get { self[ServerSideApplyPortKey.self] }
        set { self[ServerSideApplyPortKey.self] = newValue }
    }
}

// MARK: - RollbackLeasePortKey

/// `DependencyKey` for `RollbackLeasePort`.
public enum RollbackLeasePortKey: DependencyKey {
    public static let liveValue: any RollbackLeasePort = UnimplementedRollbackLeasePort()
    public static let testValue: any RollbackLeasePort = UnimplementedRollbackLeasePort()
}

public extension DependencyValues {
    /// The port that manages `coordination.k8s.io/v1/Lease` rollback mutexes.
    var rollbackLease: any RollbackLeasePort {
        get { self[RollbackLeasePortKey.self] }
        set { self[RollbackLeasePortKey.self] = newValue }
    }
}

// MARK: - ChartRepositoryPortKey

/// `DependencyKey` for `ChartRepositoryPort`.
///
/// Phase 2 port — `UnimplementedChartRepositoryPort` throws
/// `notImplementedPhase2` until a live OCI adapter is registered.
public enum ChartRepositoryPortKey: DependencyKey {
    public static let liveValue: any ChartRepositoryPort = UnimplementedChartRepositoryPort()
    public static let testValue: any ChartRepositoryPort = UnimplementedChartRepositoryPort()
}

public extension DependencyValues {
    /// The port that fetches chart metadata from OCI registries and HTTP repos.
    var chartRepository: any ChartRepositoryPort {
        get { self[ChartRepositoryPortKey.self] }
        set { self[ChartRepositoryPortKey.self] = newValue }
    }
}
