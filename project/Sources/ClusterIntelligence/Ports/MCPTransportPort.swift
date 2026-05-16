// Ports/MCPTransportPort.swift — cluster_intelligence bounded context
// DDD role: Port (primary — inbound from MCP host)
// ADR ref: ADR-0009 §Decision outcome — in-process MCP transport
// Narrative ref: domain/narrative.md §Tactical roles — MCPServerActor

import Foundation
import SharedKernel

// MARK: - MCPTransportRequest

/// An inbound tool call arriving from the MCP host over the in-process channel.
///
/// The host (`assistant_chat`) constructs this value and hands it to the
/// domain core via `MCPTransportPort`. The domain core never receives raw
/// MCP wire bytes; the adapter decodes them before calling the port.
public struct MCPTransportRequest: Sendable {
    /// Name of the tool to invoke.
    public let toolName: String
    /// JSON-encoded arguments; validated against the tool's input schema by
    /// the domain core before the policy gate runs.
    public let argumentsJSON: String
    /// The Kubernetes context this call should run against. Supplied by the
    /// host; defaults to the session's pinned context when the tool does not
    /// name one explicitly.
    public let kubernetesContextId: ContextId
    /// RFC 3339 timestamp at which the host dispatched the call.
    public let requestedAtRFC3339: String

    public init(
        toolName: String,
        argumentsJSON: String,
        kubernetesContextId: ContextId,
        requestedAtRFC3339: String
    ) {
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.kubernetesContextId = kubernetesContextId
        self.requestedAtRFC3339 = requestedAtRFC3339
    }
}

// MARK: - MCPTransportPort

/// The in-process channel between the MCP host and the domain core.
///
/// Declared in the domain core; implemented by `MCPSwiftSDKAdapter` using
/// the `modelcontextprotocol/swift-sdk`'s `InMemoryTransport` (`AsyncStream`
/// pair). The domain core never imports the MCP SDK directly.
///
/// The adapter calls `dispatch(_:)` for each inbound tool call and streams
/// the resulting `ToolResult` back over the same in-process channel.
public protocol MCPTransportPort: Sendable {
    /// Dispatches an inbound tool-call request through the domain core.
    ///
    /// The implementation must:
    /// 1. Validate `request.argumentsJSON` against the tool's input schema.
    /// 2. Run the policy gate; return a `deniedByPolicy` `ToolResult` without
    ///    making any Kubernetes API calls if the gate denies.
    /// 3. Call the Kubernetes API via `KubernetesApiPort`.
    /// 4. Truncate the response body if it exceeds `outputMaxBytes`.
    /// 5. Persist the completed `MCPInvocation` via `MCPInvocationLogPort`.
    ///
    /// - Parameter request: The decoded inbound tool call.
    /// - Returns: A `ToolResult` carrying the JSON body and invocation record.
    /// - Throws: `MCPTransportError` for fatal protocol-level failures that
    ///   cannot be expressed as a tool result.
    func dispatch(_ request: MCPTransportRequest) async throws -> ToolResult

    /// Returns the current registry snapshot for host advertisement.
    ///
    /// Called by the host during session setup and on registry version change.
    func registrySnapshot() -> MCPRegistrySnapshotReadModel
}

// MARK: - MCPTransportError

/// Errors raised by `MCPTransportPort` implementations for fatal failures.
public enum MCPTransportError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
    /// The in-process channel was closed unexpectedly.
    case channelClosed
    /// Input validation failed before the policy gate ran.
    case inputValidationFailed(toolName: String, detail: String)
}

// MARK: - UnimplementedMCPTransportPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedMCPTransportPort: MCPTransportPort {
    public init() {}

    public func dispatch(_ request: MCPTransportRequest) async throws -> ToolResult {
        throw MCPTransportError.unimplemented
    }

    public func registrySnapshot() -> MCPRegistrySnapshotReadModel {
        MCPRegistrySnapshotReadModel(from: MCPToolRegistry(version: 1, tools: []))
    }
}
