// Ports/Dependencies.swift — port_forwarding bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
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
