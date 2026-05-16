// Actors/PromptContextBuilder.swift — assistant_chat bounded context
// DDD role: DomainService (Layer 2 of ADR-0048 prompt injection defence)
// ADR ref: ADR-0048 (LLM prompt injection defence — Layer 2: untrusted-data tagging)

import Foundation

// MARK: - ContextSource

/// Discriminates the origin of a string being assembled into the LLM prompt.
///
/// The distinction determines tagging strategy: cluster-origin data always
/// receives `<UNTRUSTED_DATA>` wrapping; operator messages are passed through
/// without structural tags.
public enum ContextSource: Sendable {
    /// A Kubernetes resource value originating from the target cluster.
    ///
    /// - Parameter kind: Kubernetes resource kind (e.g. `"ConfigMap"`).
    /// - Parameter name: Resource name within the namespace.
    case clusterResource(kind: String, name: String)

    /// A result returned by an MCP tool call, treated as untrusted because
    /// it may embed cluster-origin data.
    ///
    /// - Parameter toolName: Registered MCP tool name.
    case mcpToolResult(toolName: String)

    /// A message authored directly by the human operator. Trusted; never
    /// wrapped in untrusted-data tags.
    case operatorMessage
}

// MARK: - PromptContextBuilder

/// Layer 2 of the ADR-0048 defence-in-depth model.
///
/// Wraps cluster-origin strings in `<UNTRUSTED_DATA>` structural tags before
/// they reach the LLM context window, implementing the tagging spec from
/// ADR-0048 §Layer 2.
///
/// Tag format for `clusterResource`:
/// ```
/// <UNTRUSTED_DATA source="ConfigMap/my-config">
/// <value>
/// </UNTRUSTED_DATA>
/// ```
///
/// Tag format for `mcpToolResult`:
/// ```
/// <UNTRUSTED_DATA source="mcp-tool/list-pods">
/// <value>
/// </UNTRUSTED_DATA>
/// ```
///
/// Operator messages are returned as-is without any wrapping.
///
/// Pure, stateless value type — no actor isolation required.
public struct PromptContextBuilder: Sendable {
    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Assembles a prompt fragment from a sanitized value and its source.
    ///
    /// - Parameters:
    ///   - sanitizedValue: The Layer-1 output for one cluster-origin field.
    ///   - source: The origin classification of the value.
    /// - Returns: A string ready for LLM context injection. Cluster-origin
    ///   values are wrapped; operator messages are returned verbatim.
    public func build(sanitizedValue: String, source: ContextSource) -> String {
        switch source {
        case .clusterResource(let kind, let name):
            return wrapUntrusted(sanitizedValue, sourceAttr: "\(kind)/\(name)")
        case .mcpToolResult(let toolName):
            return wrapUntrusted(sanitizedValue, sourceAttr: "mcp-tool/\(toolName)")
        case .operatorMessage:
            return sanitizedValue
        }
    }

    // MARK: - Private helpers

    private func wrapUntrusted(_ value: String, sourceAttr: String) -> String {
        "<UNTRUSTED_DATA source=\"\(sourceAttr)\">\n\(value)\n</UNTRUSTED_DATA>"
    }
}
