// MCPInProcessTransport.swift — MCPSwiftSDKAdapter target
// DDD role: Adapter (secondary — implements MCPTransportPort from cluster_intelligence)
// ADR ref: ADR-0009 §Decision outcome — in-process InMemoryTransport
// Implements: MCPTransportPort from ClusterIntelligence

import MCP
import Foundation
import Logging
import ClusterIntelligence
import ResourceBrowser
import SharedKernel

// MARK: - MCPInProcessTransport

/// In-process MCP transport that connects a domain `MCPTransportPort` to the
/// `modelcontextprotocol/swift-sdk` via `InMemoryTransport` (AsyncStream pair).
///
/// Ownership model:
/// - Owns one `Server` and one `Client`, wired through an `InMemoryTransport` pair.
/// - `MCPToolHandlers` registers tool handlers on the `Server` at init time.
/// - `dispatch(_:)` routes inbound requests through the `Client.callTool` API.
/// - The `Server` and `Client` run their message loops as long as this actor lives.
public actor MCPInProcessTransport: MCPTransportPort {

    // MARK: Private state

    private let server: Server
    private let client: Client
    private let registry: MCPToolRegistry
    private let logger: Logger

    // MARK: Init

    /// Creates and wires the in-process MCP transport.
    ///
    /// - Parameters:
    ///   - resourceListPort: Kubernetes read port forwarded into tool handlers.
    ///   - logger: Logger used for transport-level events.
    public init(
        resourceListPort: any KubernetesResourceListPort,
        logger: Logger = Logger(label: "mcp.in-process-transport")
    ) async throws {
        self.logger = logger
        self.registry = MCPToolHandlers.buildRegistry()

        // Build SDK server and client.
        let sdkServer = Server(
            name: "k8s-manager-in-process",
            version: "1.0.0",
            capabilities: Server.Capabilities(tools: .init(listChanged: false))
        )
        let sdkClient = Client(
            name: "k8s-manager-host",
            version: "1.0.0"
        )

        self.server = sdkServer
        self.client = sdkClient

        // Wire transports and register tool handlers before starting.
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        await MCPToolHandlers.registerHandlers(
            on: sdkServer,
            registry: self.registry,
            resourceListPort: resourceListPort,
            logger: logger
        )
        try await sdkServer.start(transport: serverTransport)
        _ = try await sdkClient.connect(transport: clientTransport)
        logger.info("MCPInProcessTransport ready")
    }

    // MARK: MCPTransportPort

    /// Dispatches an inbound tool-call request through the domain-defined registry,
    /// executes it via the embedded MCP `Client`, and returns a `ToolResult`.
    ///
    /// Step sequence per `MCPTransportPort` contract:
    /// 1. Registry look-up — returns `deniedByPolicy` for unknown tools.
    /// 2. JSON arguments serialised to `[String: Value]`.
    /// 3. `Client.callTool` → SDK handles JSON-RPC round-trip over in-process channel.
    /// 4. Response truncated to `outputMaxBytes`.
    /// 5. `MCPInvocation` record built and returned with `ToolResult`.
    public func dispatch(_ request: MCPTransportRequest) async throws -> ToolResult {
        let invocationId = InvocationId.generate()
        let completedAt = ISO8601DateFormatter().string(from: Date())

        guard let tool = registry.tool(named: request.toolName) else {
            return deniedResult(
                invocationId: invocationId,
                request: request,
                completedAt: completedAt,
                rule: "tool_not_registered",
                detail: "Tool '\(request.toolName)' is not in the registry."
            )
        }

        let arguments = parseArguments(request.argumentsJSON)

        do {
            let (content, isError) = try await client.callTool(
                name: request.toolName,
                arguments: arguments
            )
            return buildSuccessResult(
                invocationId: invocationId,
                request: request,
                tool: tool,
                completedAt: completedAt,
                content: content,
                isError: isError
            )
        } catch {
            let invocation = MCPInvocation(
                id: invocationId,
                toolName: request.toolName,
                requestedAtRFC3339: request.requestedAtRFC3339,
                completedAtRFC3339: completedAt,
                kubernetesContextId: request.kubernetesContextId,
                argumentsJSON: request.argumentsJSON,
                outcome: .failed(.init(reason: error.localizedDescription))
            )
            return ToolResult(resultJSON: "{}", truncated: false, invocation: invocation)
        }
    }

    /// Returns the current registry snapshot for host advertisement.
    public nonisolated func registrySnapshot() -> MCPRegistrySnapshotReadModel {
        // registry is immutable after init — safe to access nonisolated.
        MCPRegistrySnapshotReadModel(from: registry)
    }

    // MARK: Private helpers

    private func parseArguments(_ json: String) -> [String: Value]? {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: Value].self, from: data)
        else { return nil }
        return decoded
    }

    private func deniedResult(
        invocationId: InvocationId,
        request: MCPTransportRequest,
        completedAt: String,
        rule: String,
        detail: String
    ) -> ToolResult {
        let invocation = MCPInvocation(
            id: invocationId,
            toolName: request.toolName,
            requestedAtRFC3339: request.requestedAtRFC3339,
            completedAtRFC3339: completedAt,
            kubernetesContextId: request.kubernetesContextId,
            argumentsJSON: request.argumentsJSON,
            outcome: .deniedByPolicy(.init(rule: rule, detail: detail))
        )
        let body = "{\"error\":\"\(detail)\"}"
        return ToolResult(resultJSON: body, truncated: false, invocation: invocation)
    }

    private func buildSuccessResult(
        invocationId: InvocationId,
        request: MCPTransportRequest,
        tool: MCPTool,
        completedAt: String,
        content: [Tool.Content],
        isError: Bool?
    ) -> ToolResult {
        let rawJSON = contentToJSON(content)
        let (body, wasTruncated) = TruncationMarker.apply(to: rawJSON, maxBytes: tool.outputMaxBytes)
        let invocation = MCPInvocation(
            id: invocationId,
            toolName: request.toolName,
            requestedAtRFC3339: request.requestedAtRFC3339,
            completedAtRFC3339: completedAt,
            kubernetesContextId: request.kubernetesContextId,
            argumentsJSON: request.argumentsJSON,
            outcome: .succeeded(.init(
                resultJSON: body,
                resultBytes: rawJSON.utf8.count,
                truncated: wasTruncated,
                kubernetesStatusCode: isError == true ? 500 : 200
            ))
        )
        return ToolResult(resultJSON: body, truncated: wasTruncated, invocation: invocation)
    }

    private func contentToJSON(_ content: [Tool.Content]) -> String {
        let texts = content.compactMap { item -> String? in
            if case .text(let text, _, _) = item { return text }
            return nil
        }
        guard let first = texts.first else { return "{}" }
        return first
    }
}
