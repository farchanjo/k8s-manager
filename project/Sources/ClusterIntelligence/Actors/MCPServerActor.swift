// Actors/MCPServerActor.swift — cluster_intelligence bounded context
// DDD role: ApplicationService (domain actor owning the MCP wire-protocol loop)
// ADR ref: ADR-0009 §Decision outcome — in-process MCP server, policy gate, audit log
// Narrative ref: domain/narrative.md §Tactical roles — MCPServerActor

import Foundation
import Dependencies
import SharedKernel

// MARK: - MCPCallRequest

/// An inbound tool-call request presented to `MCPServerActor` by the adapter layer.
///
/// The adapter decodes raw MCP wire bytes before constructing this value, so the
/// domain actor never touches protocol framing. Mirrors the shape of
/// `MCPTransportRequest` but is positioned as the actor-facing entry point.
public struct MCPCallRequest: Sendable {
    /// Snake-case tool name as declared in the registry.
    public let toolName: String
    /// JSON-encoded arguments, validated by the adapter against the MCP input schema.
    public let argumentsJSON: String
    /// The Kubernetes context this call targets.
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

// MARK: - MCPServerError

/// Errors raised by `MCPServerActor` for conditions that cannot be expressed as
/// a well-formed `ToolResult`.
public enum MCPServerError: Error, Sendable {
    /// The tool name is not present in the registry; dispatch is refused.
    case toolNotRegistered(name: String)
    /// The policy engine itself failed (distinct from a deny decision).
    case policyEngineFailed(detail: String)
}

// MARK: - MCPServerActor

/// Domain actor that owns the in-process MCP wire-protocol dispatch loop.
///
/// Responsibilities (per ADR-0009):
/// 1. Registry look-up — returns `deniedByPolicy` for unknown tools.
/// 2. Policy evaluation via `@Dependency(\.toolPolicy)`.
/// 3. Result truncation to 256 KiB (per-tool `outputMaxBytes`).
/// 4. Audit persistence via `@Dependency(\.mcpInvocationLog)`.
///
/// All pending invocations are tracked in `pendingInvocations` so callers can
/// correlate in-flight work with their `UUID` handles.
public actor MCPServerActor {

    // MARK: State

    private let registry: MCPToolRegistry
    private var pendingInvocations: [UUID: MCPInvocation]

    // MARK: Init

    /// Creates the actor with the given tool registry.
    ///
    /// - Parameter registry: The catalogue of tools the server advertises.
    public init(registry: MCPToolRegistry) {
        self.registry = registry
        self.pendingInvocations = [:]
    }

    // MARK: Public interface

    /// Handles one inbound tool call end-to-end.
    ///
    /// Step sequence:
    /// 1. Registry look-up — throws `MCPServerError.toolNotRegistered` when unknown.
    /// 2. Policy gate via `\.toolPolicy` — records `deniedByPolicy` and returns
    ///    without making any Kubernetes API calls if denied.
    /// 3. Delegates to the registered `\.mcpTransport` for Kubernetes execution.
    /// 4. Truncates the result body to `tool.outputMaxBytes` (≤ 256 KiB).
    /// 5. Appends the completed `MCPInvocation` to `\.mcpInvocationLog`.
    ///
    /// - Parameter call: The decoded inbound tool-call request.
    /// - Returns: A `ToolResult` carrying the JSON body and auditable invocation record.
    /// - Throws: `MCPServerError` for fatal pre-dispatch failures.
    public func handle(call: MCPCallRequest) async throws -> ToolResult {
        guard let tool = registry.tool(named: call.toolName) else {
            throw MCPServerError.toolNotRegistered(name: call.toolName)
        }

        let invocationId = InvocationId.generate()
        let completedAt = ISO8601DateFormatter().string(from: Date())

        @Dependency(\.toolPolicy) var policyPort
        let policyRequest = PolicyEvaluationRequest(
            tool: tool,
            argumentsJSON: call.argumentsJSON,
            kubernetesContextId: call.kubernetesContextId
        )

        let decision: PolicyDecision
        do {
            decision = try await policyPort.evaluate(policyRequest)
        } catch {
            throw MCPServerError.policyEngineFailed(detail: error.localizedDescription)
        }

        if case .denied(let rule, let detail) = decision {
            return buildDeniedResult(
                invocationId: invocationId,
                call: call,
                completedAt: completedAt,
                rule: rule,
                detail: detail
            )
        }

        @Dependency(\.mcpTransport) var transport
        let transportRequest = MCPTransportRequest(
            toolName: call.toolName,
            argumentsJSON: call.argumentsJSON,
            kubernetesContextId: call.kubernetesContextId,
            requestedAtRFC3339: call.requestedAtRFC3339
        )
        let rawResult = try await transport.dispatch(transportRequest)
        let (body, wasTruncated) = TruncationMarker.apply(
            to: rawResult.resultJSON,
            maxBytes: tool.outputMaxBytes
        )
        let outcome = MCPOutcome.succeeded(.init(
            resultJSON: body,
            resultBytes: rawResult.resultJSON.utf8.count,
            truncated: wasTruncated,
            kubernetesStatusCode: 200
        ))
        let invocation = MCPInvocation(
            id: invocationId,
            toolName: call.toolName,
            requestedAtRFC3339: call.requestedAtRFC3339,
            completedAtRFC3339: completedAt,
            kubernetesContextId: call.kubernetesContextId,
            argumentsJSON: call.argumentsJSON,
            outcome: outcome
        )
        pendingInvocations[invocationId.rawValue] = invocation

        @Dependency(\.mcpInvocationLog) var log
        try await log.append(invocation)
        pendingInvocations.removeValue(forKey: invocationId.rawValue)

        return ToolResult(resultJSON: body, truncated: wasTruncated, invocation: invocation)
    }

    /// Returns an immutable snapshot of the current tool registry.
    ///
    /// Used by the host to advertise the tool list without holding actor isolation.
    public func registrySnapshot() -> MCPToolRegistry {
        registry
    }

    // MARK: Private helpers

    private func buildDeniedResult(
        invocationId: InvocationId,
        call: MCPCallRequest,
        completedAt: String,
        rule: String,
        detail: String
    ) -> ToolResult {
        let invocation = MCPInvocation(
            id: invocationId,
            toolName: call.toolName,
            requestedAtRFC3339: call.requestedAtRFC3339,
            completedAtRFC3339: completedAt,
            kubernetesContextId: call.kubernetesContextId,
            argumentsJSON: call.argumentsJSON,
            outcome: .deniedByPolicy(.init(rule: rule, detail: detail))
        )
        let body = "{\"error\":\"\(detail)\"}"
        return ToolResult(resultJSON: body, truncated: false, invocation: invocation)
    }
}
