// Ports/Dependencies.swift — resource_browser bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
import SharedKernel

// MARK: - KubernetesResourceListPortKey

/// `DependencyKey` for `KubernetesResourceListPort`.
///
/// Both `liveValue` and `testValue` are the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at the composition root.
public enum KubernetesResourceListPortKey: DependencyKey {
    public static let liveValue: any KubernetesResourceListPort =
        UnimplementedKubernetesResourceListPort()
    public static let testValue: any KubernetesResourceListPort =
        UnimplementedKubernetesResourceListPort()
}

public extension DependencyValues {
    /// The port that fetches and lists Kubernetes resources.
    var kubernetesResourceList: any KubernetesResourceListPort {
        get { self[KubernetesResourceListPortKey.self] }
        set { self[KubernetesResourceListPortKey.self] = newValue }
    }
}

// MARK: - KubernetesResourceMutationPortKey

/// `DependencyKey` for `KubernetesResourceMutationPort`.
public enum KubernetesResourceMutationPortKey: DependencyKey {
    public static let liveValue: any KubernetesResourceMutationPort =
        UnimplementedKubernetesResourceMutationPort()
    public static let testValue: any KubernetesResourceMutationPort =
        UnimplementedKubernetesResourceMutationPort()
}

public extension DependencyValues {
    /// The port that dispatches approved mutation commands to the Kubernetes API.
    var kubernetesResourceMutation: any KubernetesResourceMutationPort {
        get { self[KubernetesResourceMutationPortKey.self] }
        set { self[KubernetesResourceMutationPortKey.self] = newValue }
    }
}

// MARK: - MutationAuditPortKey

/// `DependencyKey` for `MutationAuditPort`.
public enum MutationAuditPortKey: DependencyKey {
    public static let liveValue: any MutationAuditPort = UnimplementedMutationAuditPort()
    public static let testValue: any MutationAuditPort = UnimplementedMutationAuditPort()
}

public extension DependencyValues {
    /// The port that persists audit entries to the `cluster_mutation_audit` table.
    var mutationAudit: any MutationAuditPort {
        get { self[MutationAuditPortKey.self] }
        set { self[MutationAuditPortKey.self] = newValue }
    }
}

// MARK: - DraftStoragePortKey

/// `DependencyKey` for `DraftStoragePort`.
public enum DraftStoragePortKey: DependencyKey {
    public static let liveValue: any DraftStoragePort = UnimplementedDraftStoragePort()
    public static let testValue: any DraftStoragePort = UnimplementedDraftStoragePort()
}

public extension DependencyValues {
    /// The port that persists and retrieves `Draft` entities.
    var draftStorage: any DraftStoragePort {
        get { self[DraftStoragePortKey.self] }
        set { self[DraftStoragePortKey.self] = newValue }
    }
}

// MARK: - ResourceWatchPortKey

/// `DependencyKey` for `ResourceWatchPort`.
public enum ResourceWatchPortKey: DependencyKey {
    public static let liveValue: any ResourceWatchPort = UnimplementedResourceWatchPort()
    public static let testValue: any ResourceWatchPort = UnimplementedResourceWatchPort()
}

public extension DependencyValues {
    /// The port that opens long-lived Kubernetes watch streams.
    var resourceWatch: any ResourceWatchPort {
        get { self[ResourceWatchPortKey.self] }
        set { self[ResourceWatchPortKey.self] = newValue }
    }
}

// MARK: - WatchStreamCoordinatorKey

/// `DependencyKey` for `WatchStreamCoordinator`.
///
/// Both `liveValue` and `testValue` are fresh instances with the default budget.
/// The composition root registers a singleton via `prepareDependencies` at
/// startup (ADR-0020) so the same coordinator is shared across the process.
public enum WatchStreamCoordinatorKey: DependencyKey {
    public static let liveValue: WatchStreamCoordinator = WatchStreamCoordinator()
    public static let testValue: WatchStreamCoordinator = WatchStreamCoordinator()
}

public extension DependencyValues {
    /// The coordinator that owns tab-level watch stream lifecycle.
    var watchStreamCoordinator: WatchStreamCoordinator {
        get { self[WatchStreamCoordinatorKey.self] }
        set { self[WatchStreamCoordinatorKey.self] = newValue }
    }
}

// MARK: - PodLogsPortKey

/// `DependencyKey` for `PodLogsPort`.
///
/// Both `liveValue` and `testValue` are the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at the composition root.
public enum PodLogsPortKey: DependencyKey {
    public static let liveValue: any PodLogsPort = UnimplementedPodLogsPort()
    public static let testValue: any PodLogsPort = UnimplementedPodLogsPort()
}

public extension DependencyValues {
    /// The port that streams pod container logs.
    var podLogs: any PodLogsPort {
        get { self[PodLogsPortKey.self] }
        set { self[PodLogsPortKey.self] = newValue }
    }
}
