// Domain/MCPToolRegistry.swift — cluster_intelligence bounded context
// DDD role: AggregateRoot (MCPToolRegistry) + Entity (MCPTool)
// CUE source: docs/arch/contexts/cluster_intelligence/schemas/mcp_tool_registry.cue
// Narrative ref: domain/narrative.md §Tactical roles — MCPToolRegistry, §Tool registry (MVP+)

import Foundation

// MARK: - KubernetesVerb

/// The closed set of HTTP verbs a read-only tool may issue.
///
/// Mirrors `#KubernetesVerb` from `mcp_tool_registry.cue`. The policy gate
/// denies any verb outside this set; no tool may ever carry a mutating verb.
public enum KubernetesVerb: String, Hashable, Sendable, Codable, CaseIterable {
    case get
    case list
    case watch
}

// MARK: - MCPTool

/// A single tool descriptor advertised by the in-process MCP server.
///
/// Mirrors `#MCPTool` from `mcp_tool_registry.cue`. Identified by `name`
/// within the registry. Adding, removing, or modifying a tool requires an ADR
/// and bumps the registry `version`.
public struct MCPTool: Hashable, Sendable, Codable {
    /// Snake-case name, globally unique within this registry.
    public let name: String
    /// Human-readable description surfaced in the tool list.
    public let description: String
    /// JSON Schema (draft-2020-12) literal. Inputs are validated against this
    /// before the policy gate runs.
    public let inputJSONSchema: String
    /// Closed set of Kubernetes verbs this tool may issue.
    public let kubernetesVerbs: [KubernetesVerb]
    /// Closed set of Kubernetes resource kinds this tool may touch.
    public let resources: [String]
    /// When `true` the tool inherits the session's pinned context; when
    /// `false` the caller may supply an explicit `contextId` argument.
    public let requiresPinnedContext: Bool
    /// Maximum byte count of the JSON body returned to the host. Payloads
    /// exceeding this limit are truncated with the defined marker.
    /// Default per CUE schema: 256 KiB.
    public let outputMaxBytes: Int

    public init(
        name: String,
        description: String,
        inputJSONSchema: String,
        kubernetesVerbs: [KubernetesVerb],
        resources: [String],
        requiresPinnedContext: Bool,
        outputMaxBytes: Int = 262_144
    ) {
        self.name = name
        self.description = description
        self.inputJSONSchema = inputJSONSchema
        self.kubernetesVerbs = kubernetesVerbs
        self.resources = resources
        self.requiresPinnedContext = requiresPinnedContext
        self.outputMaxBytes = outputMaxBytes
    }
}

// MARK: - MCPToolRegistry

/// The authoritative catalogue of tools the in-process MCP server advertises.
///
/// Mirrors `#MCPToolRegistry` from `mcp_tool_registry.cue`. Treated as an
/// aggregate root: the registry is replaced wholesale when its shape changes,
/// and `version` is bumped with every such replacement. The host
/// (`assistant_chat`) caches the registry by version; a change in version
/// triggers a re-advertisement cycle.
///
/// Invariant: every registered tool's `kubernetesVerbs` must be a subset of
/// `{get, list, watch}`. `MCPToolRegistry` enforces this at initialisation.
public struct MCPToolRegistry: Sendable {
    /// Bumped on every registry shape change. Consumers cache by this value.
    public let version: Int
    /// All tools this registry advertises to the LLM host.
    public let tools: [MCPTool]

    /// The tool names in `tools`, stored for O(1) look-up.
    private let toolIndex: [String: MCPTool]

    /// Initialises a registry, asserting the read-only invariant.
    ///
    /// - Parameters:
    ///   - version: Registry version number (≥ 1).
    ///   - tools: Tool descriptors. All verbs must be in `{get, list, watch}`.
    /// - Precondition: `version >= 1`
    /// - Precondition: Every tool's `kubernetesVerbs` is a subset of
    ///   `KubernetesVerb.allCases`.
    public init(version: Int, tools: [MCPTool]) {
        precondition(version >= 1, "Registry version must be ≥ 1")
        self.version = version
        self.tools = tools
        self.toolIndex = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
    }

    /// Looks up a tool by its snake-case name.
    ///
    /// - Parameter name: The tool name to look up.
    /// - Returns: The `MCPTool` entry, or `nil` if not registered.
    public func tool(named name: String) -> MCPTool? {
        toolIndex[name]
    }
}

// MARK: - MCPRegistrySnapshotReadModel

/// Lightweight projection consumed by `assistant_chat` to advertise tool
/// descriptors to the LLM. Does not expose the full registry aggregate.
public struct MCPRegistrySnapshotReadModel: Sendable {
    /// Registry version at snapshot time.
    public let version: Int
    /// Tool names and descriptions for advertising.
    public let toolDescriptors: [(name: String, description: String)]

    public init(from registry: MCPToolRegistry) {
        version = registry.version
        toolDescriptors = registry.tools.map { ($0.name, $0.description) }
    }
}

// MARK: - MCPInvocationLogReadModel

/// Lightweight projection consumed by the diagnostics panel in `app_shell`.
/// Carries the recent N invocations with their outcomes.
public struct MCPInvocationLogReadModel: Sendable {
    public let entries: [MCPInvocation]

    public init(entries: [MCPInvocation]) {
        self.entries = entries
    }
}
