// Ports/Dependencies.swift — cluster_connectivity bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
import SharedKernel

// MARK: - KubeconfigLoaderPortKey

/// `DependencyKey` for `KubeconfigLoaderPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at composition root.
public enum KubeconfigLoaderPortKey: DependencyKey {
    public static let liveValue: any KubeconfigLoaderPort = UnimplementedKubeconfigLoaderPort()
    public static let testValue: any KubeconfigLoaderPort = UnimplementedKubeconfigLoaderPort()
}

public extension DependencyValues {
    /// The port responsible for loading kubeconfig files from disk.
    var kubeconfigLoader: any KubeconfigLoaderPort {
        get { self[KubeconfigLoaderPortKey.self] }
        set { self[KubeconfigLoaderPortKey.self] = newValue }
    }
}

// MARK: - KubernetesApiPortKey

/// `DependencyKey` for `KubernetesApiPort`.
public enum KubernetesApiPortKey: DependencyKey {
    public static let liveValue: any KubernetesApiPort = UnimplementedKubernetesApiPort()
    public static let testValue: any KubernetesApiPort = UnimplementedKubernetesApiPort()
}

public extension DependencyValues {
    /// The port that probes cluster health and fetches server metadata.
    var kubernetesApi: any KubernetesApiPort {
        get { self[KubernetesApiPortKey.self] }
        set { self[KubernetesApiPortKey.self] = newValue }
    }
}

// MARK: - WatchPortKey

/// `DependencyKey` for `WatchPort`.
public enum WatchPortKey: DependencyKey {
    public static let liveValue: any WatchPort = UnimplementedWatchPort()
    public static let testValue: any WatchPort = UnimplementedWatchPort()
}

public extension DependencyValues {
    /// The port that streams domain events from a `ClusterSessionActor`.
    var watchPort: any WatchPort {
        get { self[WatchPortKey.self] }
        set { self[WatchPortKey.self] = newValue }
    }
}

// MARK: - ExecPluginPortKey

/// `DependencyKey` for `ExecPluginPort`.
public enum ExecPluginPortKey: DependencyKey {
    public static let liveValue: any ExecPluginPort = UnimplementedExecPluginPort()
    public static let testValue: any ExecPluginPort = UnimplementedExecPluginPort()
}

public extension DependencyValues {
    /// The port that invokes external exec credential plugins.
    var execPlugin: any ExecPluginPort {
        get { self[ExecPluginPortKey.self] }
        set { self[ExecPluginPortKey.self] = newValue }
    }
}
