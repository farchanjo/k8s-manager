// Ports/ToolDispatcherPort.swift — assistant_chat bounded context
// DDD role: Port (outbound — MCP bridge)
// ADR ref: ADR-0009 (MCP host architecture); ADR-0020 (DI strategy)

import Foundation
import SharedKernel

// MARK: - ToolRequest

/// A single tool-use request assembled from the LLM stream.
public struct ToolRequest: Sendable {
    /// Opaque call identifier produced by the provider stream (1–128 chars).
    public let callId: String
    /// Registered tool name (lowercase, max 64 characters).
    public let toolName: String
    /// Verbatim assembled arguments JSON string produced by the model.
    public let argumentsJSON: String
    /// Kubernetes context to scope the tool call against, when pinned.
    public let pinnedContextId: ContextId?

    public init(
        callId: String,
        toolName: String,
        argumentsJSON: String,
        pinnedContextId: ContextId? = nil
    ) {
        self.callId = callId
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.pinnedContextId = pinnedContextId
    }
}

// MARK: - ToolResponse

/// Result of one tool-use round trip, ready to feed back to the provider.
public struct ToolResponse: Sendable {
    /// Echo of the originating `callId`.
    public let callId: String
    /// Result JSON string, truncated to 256 KiB by the MCP server (ADR-0009).
    public let resultJSON: String
    /// Final status of the call.
    public let status: ToolCallStatus

    public init(callId: String, resultJSON: String, status: ToolCallStatus) {
        self.callId = callId
        self.resultJSON = resultJSON
        self.status = status
    }
}

// MARK: - ToolDispatcherPort

/// Bridges one LLM-requested tool call to the in-process MCP server and
/// translates the result back into a `tool_result` part for the next provider
/// turn.
///
/// Declared in the domain core; implemented by `MCPSwiftSDKAdapter` in
/// infrastructure. The domain core never imports `modelcontextprotocol/swift-sdk`.
public protocol ToolDispatcherPort: Sendable {
    /// Executes the tool described by `request` against the in-process MCP
    /// server scoped to `request.pinnedContextId`.
    ///
    /// Requests for unregistered tools return a `ToolResponse` with
    /// `status == .deniedByPolicy` without raising an error.
    ///
    /// - Parameter request: The assembled tool-use request from the LLM stream.
    /// - Returns: A `ToolResponse` with the result or denial detail.
    /// - Throws: `ToolDispatcherError` on unrecoverable MCP errors.
    func dispatch(request: ToolRequest) async throws -> ToolResponse
}

// MARK: - ToolDispatcherError

/// Errors raised by `ToolDispatcherPort` implementations.
public enum ToolDispatcherError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
    /// The MCP server is unavailable or returned a transport-level error.
    case mcpUnavailable(detail: String)
    /// Arguments could not be decoded into the tool's expected schema.
    case malformedArguments(toolName: String, detail: String)
}

// MARK: - UnimplementedToolDispatcherPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedToolDispatcherPort: ToolDispatcherPort {
    public init() {}

    public func dispatch(request: ToolRequest) async throws -> ToolResponse {
        throw ToolDispatcherError.unimplemented
    }
}
