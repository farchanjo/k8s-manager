// Ports/Dependencies.swift — cluster_intelligence bounded context
// DI registry via pointfreeco/swift-dependencies
// ADR ref: ADR-0020 (dependency injection strategy)

import Dependencies
import SharedKernel

// MARK: - MCPTransportPortKey

/// `DependencyKey` for `MCPTransportPort`.
///
/// `liveValue` and `testValue` are both the `Unimplemented` sentinel so the
/// build is clean with no adapter linked. `MCPSwiftSDKAdapter` overrides
/// `liveValue` at composition root.
public enum MCPTransportPortKey: DependencyKey {
    public static let liveValue: any MCPTransportPort = UnimplementedMCPTransportPort()
    public static let testValue: any MCPTransportPort = UnimplementedMCPTransportPort()
}

public extension DependencyValues {
    /// The in-process MCP transport channel between the host and domain core.
    var mcpTransport: any MCPTransportPort {
        get { self[MCPTransportPortKey.self] }
        set { self[MCPTransportPortKey.self] = newValue }
    }
}

// MARK: - ToolPolicyPortKey

/// `DependencyKey` for `ToolPolicyPort`.
public enum ToolPolicyPortKey: DependencyKey {
    public static let liveValue: any ToolPolicyPort = UnimplementedToolPolicyPort()
    public static let testValue: any ToolPolicyPort = UnimplementedToolPolicyPort()
}

public extension DependencyValues {
    /// The Rego-backed policy gate that allow-lists tool invocations.
    var toolPolicy: any ToolPolicyPort {
        get { self[ToolPolicyPortKey.self] }
        set { self[ToolPolicyPortKey.self] = newValue }
    }
}

// MARK: - MCPInvocationLogPortKey

/// `DependencyKey` for `MCPInvocationLogPort`.
public enum MCPInvocationLogPortKey: DependencyKey {
    public static let liveValue: any MCPInvocationLogPort = UnimplementedMCPInvocationLogPort()
    public static let testValue: any MCPInvocationLogPort = UnimplementedMCPInvocationLogPort()
}

public extension DependencyValues {
    /// The port that persists and retrieves MCP invocation audit-log entries.
    var mcpInvocationLog: any MCPInvocationLogPort {
        get { self[MCPInvocationLogPortKey.self] }
        set { self[MCPInvocationLogPortKey.self] = newValue }
    }
}
