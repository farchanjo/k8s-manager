// MCPToolHandlers.swift — MCPSwiftSDKAdapter target
// DDD role: Adapter helper — maps MCP tool calls to KubernetesResourceListPort
// ADR ref: ADR-0009 §MVP+ read-only tool registry, ADR-0003 (read-only invariant)

import MCP
import Foundation
import Logging
import ClusterIntelligence
import ResourceBrowser
import SharedKernel

// MARK: - MCPToolHandlers

/// Registers the curated read-only tool set on an MCP `Server` and provides
/// the static `MCPToolRegistry` that matches those registrations.
///
/// Tool set (ADR-0009 MVP+ subset mapped to `KubernetesResourceListPort`):
/// - `kube_get_pod`
/// - `kube_list_pods`
/// - `kube_list_deployments`
/// - `kube_get_service`
/// - `kube_get_namespace`
/// - `kube_list_events`
public enum MCPToolHandlers {

    // MARK: Registry

    /// Builds the `MCPToolRegistry` that matches the handlers registered below.
    public static func buildRegistry() -> MCPToolRegistry {
        MCPToolRegistry(version: 1, tools: toolDescriptors)
    }

    // MARK: Handler registration

    /// Registers all read-only tool handlers on `server`.
    ///
    /// Each handler converts MCP `[String: Value]` arguments into
    /// `KubernetesResourceListPort` calls, serialises the result as JSON,
    /// and returns an MCP `CallTool.Result` text block.
    public static func registerHandlers(
        on server: Server,
        registry: MCPToolRegistry,
        resourceListPort: any KubernetesResourceListPort,
        logger: Logger
    ) async {
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: registry.tools.map(sdkTool(from:)))
        }

        await server.withMethodHandler(CallTool.self) { params in
            let name = params.name
            let args = params.arguments ?? [:]
            guard registry.tool(named: name) != nil else {
                return CallTool.Result(
                    content: [.text(text: "{\"error\":\"tool_not_registered\"}", annotations: nil, _meta: nil)],
                    isError: true
                )
            }
            do {
                let json = try await Self.dispatch(
                    toolName: name,
                    args: args,
                    resourceListPort: resourceListPort,
                    logger: logger
                )
                return CallTool.Result(
                    content: [.text(text: json, annotations: nil, _meta: nil)]
                )
            } catch {
                let body = "{\"error\":\"\(error.localizedDescription)\"}"
                return CallTool.Result(
                    content: [.text(text: body, annotations: nil, _meta: nil)],
                    isError: true
                )
            }
        }
    }

    // MARK: Tool dispatch

    private static func dispatch(
        toolName: String,
        args: [String: Value],
        resourceListPort: any KubernetesResourceListPort,
        logger: Logger
    ) async throws -> String {
        let clusterId = ClusterId(stringArg(args, "contextId") ?? "")
        let namespace = stringArg(args, "namespace")
        switch toolName {
        case "kube_get_pod":
            return try await getPod(args: args, clusterId: clusterId, namespace: namespace, port: resourceListPort)
        case "kube_list_pods":
            return try await listResources(gvk: .core("Pod"), clusterId: clusterId, namespace: namespace, port: resourceListPort)
        case "kube_list_deployments":
            return try await listResources(gvk: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"), clusterId: clusterId, namespace: namespace, port: resourceListPort)
        case "kube_get_service":
            return try await getResource(gvk: .core("Service"), args: args, clusterId: clusterId, namespace: namespace, port: resourceListPort)
        case "kube_get_namespace":
            return try await getResource(gvk: .core("Namespace"), args: args, clusterId: clusterId, namespace: nil, port: resourceListPort)
        case "kube_list_events":
            return try await listResources(gvk: .core("Event"), clusterId: clusterId, namespace: namespace, port: resourceListPort)
        default:
            return "{\"error\":\"unknown_tool\"}"
        }
    }

    // MARK: Individual handlers

    private static func getPod(
        args: [String: Value],
        clusterId: ClusterId,
        namespace: String?,
        port: any KubernetesResourceListPort
    ) async throws -> String {
        let name = stringArg(args, "name") ?? ""
        let detail = try await port.get(gvk: .core("Pod"), name: name, namespace: namespace, clusterId: clusterId)
        return detail.rawJSON
    }

    private static func listResources(
        gvk: GroupVersionKind,
        clusterId: ClusterId,
        namespace: String?,
        port: any KubernetesResourceListPort
    ) async throws -> String {
        let items = try await port.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(items)
        return String(decoding: data, as: UTF8.self)
    }

    private static func getResource(
        gvk: GroupVersionKind,
        args: [String: Value],
        clusterId: ClusterId,
        namespace: String?,
        port: any KubernetesResourceListPort
    ) async throws -> String {
        let name = stringArg(args, "name") ?? ""
        let detail = try await port.get(gvk: gvk, name: name, namespace: namespace, clusterId: clusterId)
        return detail.rawJSON
    }

    // MARK: Argument helpers

    private static func stringArg(_ args: [String: Value], _ key: String) -> String? {
        args[key]?.stringValue
    }

    // MARK: SDK tool builder

    private static func sdkTool(from mcpTool: MCPTool) -> Tool {
        let schema: Value
        if let data = mcpTool.inputJSONSchema.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Value.self, from: data) {
            schema = decoded
        } else {
            schema = .object(["type": .string("object"), "properties": .object([:])])
        }
        return Tool(
            name: mcpTool.name,
            description: mcpTool.description,
            inputSchema: schema,
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true)
        )
    }

    // MARK: Static tool descriptors

    private static let toolDescriptors: [MCPTool] = [
        MCPTool(
            name: "kube_get_pod",
            description: "Fetches the full detail for a single Pod by name and namespace.",
            inputJSONSchema: """
            {"type":"object","properties":{"name":{"type":"string"},"namespace":{"type":"string"},"contextId":{"type":"string"}},"required":["name"]}
            """,
            kubernetesVerbs: [.get],
            resources: ["pods"],
            requiresPinnedContext: true
        ),
        MCPTool(
            name: "kube_list_pods",
            description: "Lists Pods in a namespace (or across all namespaces when omitted).",
            inputJSONSchema: """
            {"type":"object","properties":{"namespace":{"type":"string"},"contextId":{"type":"string"}},"required":[]}
            """,
            kubernetesVerbs: [.list],
            resources: ["pods"],
            requiresPinnedContext: true
        ),
        MCPTool(
            name: "kube_list_deployments",
            description: "Lists Deployments in a namespace (or across all namespaces when omitted).",
            inputJSONSchema: """
            {"type":"object","properties":{"namespace":{"type":"string"},"contextId":{"type":"string"}},"required":[]}
            """,
            kubernetesVerbs: [.list],
            resources: ["deployments"],
            requiresPinnedContext: true
        ),
        MCPTool(
            name: "kube_get_service",
            description: "Fetches the full detail for a single Service by name and namespace.",
            inputJSONSchema: """
            {"type":"object","properties":{"name":{"type":"string"},"namespace":{"type":"string"},"contextId":{"type":"string"}},"required":["name"]}
            """,
            kubernetesVerbs: [.get],
            resources: ["services"],
            requiresPinnedContext: true
        ),
        MCPTool(
            name: "kube_get_namespace",
            description: "Fetches the full detail for a single Namespace by name.",
            inputJSONSchema: """
            {"type":"object","properties":{"name":{"type":"string"},"contextId":{"type":"string"}},"required":["name"]}
            """,
            kubernetesVerbs: [.get],
            resources: ["namespaces"],
            requiresPinnedContext: true
        ),
        MCPTool(
            name: "kube_list_events",
            description: "Lists Events in a namespace (or across all namespaces when omitted).",
            inputJSONSchema: """
            {"type":"object","properties":{"namespace":{"type":"string"},"contextId":{"type":"string"}},"required":[]}
            """,
            kubernetesVerbs: [.list],
            resources: ["events"],
            requiresPinnedContext: true
        ),
    ]
}
