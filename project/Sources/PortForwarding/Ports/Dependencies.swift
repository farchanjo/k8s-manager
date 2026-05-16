// Ports/Dependencies.swift — port_forwarding bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
import Foundation
import SharedKernel

// MARK: - PortForwardChannelPortKey

/// `DependencyKey` for ``PortForwardChannelPort``.
///
/// Both `liveValue` and `testValue` resolve to the `Unimplemented` sentinel so
/// the build is clean with no adapter linked. `WebSocketPortForwardAdapter`
/// overrides `liveValue` at the composition root.
public enum PortForwardChannelPortKey: DependencyKey {
    public static let liveValue: any PortForwardChannelPort = UnimplementedPortForwardChannelPort()
    public static let testValue: any PortForwardChannelPort = UnimplementedPortForwardChannelPort()
}

public extension DependencyValues {
    /// The port that manages `portforward.k8s.io` WebSocket connections.
    var portForwardChannel: any PortForwardChannelPort {
        get { self[PortForwardChannelPortKey.self] }
        set { self[PortForwardChannelPortKey.self] = newValue }
    }
}

// MARK: - PortForwardLifecyclePortKey

/// `DependencyKey` for ``PortForwardLifecyclePort``.
///
/// Both `liveValue` and `testValue` resolve to the `Unimplemented` sentinel.
/// `PortForwardManagerActor` overrides `liveValue` at the composition root.
public enum PortForwardLifecyclePortKey: DependencyKey {
    public static let liveValue: any PortForwardLifecyclePort = UnimplementedPortForwardLifecyclePort()
    public static let testValue: any PortForwardLifecyclePort = UnimplementedPortForwardLifecyclePort()
}

public extension DependencyValues {
    /// The port that starts and stops port-forward sessions.
    var portForwardLifecycle: any PortForwardLifecyclePort {
        get { self[PortForwardLifecyclePortKey.self] }
        set { self[PortForwardLifecyclePortKey.self] = newValue }
    }
}

// MARK: - ServiceEndpointReaderPortKey

/// `DependencyKey` for ``ServiceEndpointReaderPort``.
///
/// Both `liveValue` and `testValue` resolve to the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. The infrastructure adapter implementing
/// the EndpointSlice query overrides `liveValue` at the composition root.
public enum ServiceEndpointReaderPortKey: DependencyKey {
    public static let liveValue: any ServiceEndpointReaderPort = UnimplementedServiceEndpointReaderPort()
    public static let testValue: any ServiceEndpointReaderPort = UnimplementedServiceEndpointReaderPort()
}

public extension DependencyValues {
    /// The port that resolves a Kubernetes Service to its backing Pod targets.
    var serviceEndpointReader: any ServiceEndpointReaderPort {
        get { self[ServiceEndpointReaderPortKey.self] }
        set { self[ServiceEndpointReaderPortKey.self] = newValue }
    }
}

// MARK: - PortForwardRepositoryPortKey

/// `DependencyKey` for ``PortForwardRepositoryPort``.
///
/// Both `liveValue` and `testValue` resolve to the `Unimplemented` sentinel.
/// The `GRDBPortForwardRepositoryAdapter` overrides `liveValue` at the composition root.
public enum PortForwardRepositoryPortKey: DependencyKey {
    public static let liveValue: any PortForwardRepositoryPort = UnimplementedPortForwardRepositoryPort()
    public static let testValue: any PortForwardRepositoryPort = UnimplementedPortForwardRepositoryPort()
}

public extension DependencyValues {
    /// The port that persists ``PortForwardSession`` aggregates to SQLite.
    var portForwardRepository: any PortForwardRepositoryPort {
        get { self[PortForwardRepositoryPortKey.self] }
        set { self[PortForwardRepositoryPortKey.self] = newValue }
    }
}
