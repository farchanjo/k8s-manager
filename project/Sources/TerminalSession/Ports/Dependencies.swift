// Ports/Dependencies.swift — terminal_session bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies

// MARK: - PodExecPortKey

/// `DependencyKey` for `PodExecPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. Adapter targets override `liveValue`
/// at composition root.
public enum PodExecPortKey: DependencyKey {
    public static let liveValue: any PodExecPort = UnimplementedPodExecPort()
    public static let testValue: any PodExecPort = UnimplementedPodExecPort()
}

public extension DependencyValues {
    /// The port that opens WebSocket exec connections to the Kubernetes API server.
    var podExec: any PodExecPort {
        get { self[PodExecPortKey.self] }
        set { self[PodExecPortKey.self] = newValue }
    }
}

// MARK: - NodeDebugPortKey

/// `DependencyKey` for `NodeDebugPort`.
public enum NodeDebugPortKey: DependencyKey {
    public static let liveValue: any NodeDebugPort = UnimplementedNodeDebugPort()
    public static let testValue: any NodeDebugPort = UnimplementedNodeDebugPort()
}

public extension DependencyValues {
    /// The port that creates and deletes ephemeral debug Pods on Kubernetes nodes.
    var nodeDebug: any NodeDebugPort {
        get { self[NodeDebugPortKey.self] }
        set { self[NodeDebugPortKey.self] = newValue }
    }
}

// MARK: - TerminalRepositoryPortKey

/// `DependencyKey` for `TerminalRepositoryPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. The `GRDBPersistenceAdapter` target
/// overrides `liveValue` at the composition root.
public enum TerminalRepositoryPortKey: DependencyKey {
    public static let liveValue: any TerminalRepositoryPort = UnimplementedTerminalRepository()
    public static let testValue: any TerminalRepositoryPort = UnimplementedTerminalRepository()
}

public extension DependencyValues {
    /// The port that persists `TerminalSession` metadata to local SQLite storage.
    var terminalRepository: any TerminalRepositoryPort {
        get { self[TerminalRepositoryPortKey.self] }
        set { self[TerminalRepositoryPortKey.self] = newValue }
    }
}
