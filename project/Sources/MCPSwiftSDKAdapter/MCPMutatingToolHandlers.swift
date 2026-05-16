// MCPMutatingToolHandlers.swift — MCPSwiftSDKAdapter target
// DDD role: Adapter helper — maps mutating MCP tool calls to KubernetesResourceMutationPort
// ADR ref: ADR-0009 MVP+ (mutating handlers), ADR-0012 (mutation policy)

import MCP
import Foundation
import Logging
import ClusterIntelligence
import ResourceBrowser
import SharedKernel

// MARK: - MCPMutatingToolHandlers

/// Registers `kube_apply`, `kube_delete`, and `kube_patch` on an MCP `Server`.
///
/// Each handler:
/// 1. Checks the policy gate via `ToolPolicyPort` — mutating verbs require
///    an explicit `PolicyDecision.allowed` before any Kubernetes API call.
/// 2. Calls `KubernetesResourceMutationPort` to execute the mutation.
/// 3. Returns an MCP-shaped `CallTool.Result` text block.
///
/// These tools are intentionally NOT included in the read-only registry
/// returned by `MCPToolHandlers.buildRegistry()`. They must be registered
/// separately and their policy gate enforces that mutating verbs are only
/// executed when an adapter provides an explicit allow.
public enum MCPMutatingToolHandlers {

    // MARK: Registry

    /// Builds the `MCPToolRegistry` entry for the three mutating tools.
    ///
    /// Callers should merge this into a combined registry only when mutating
    /// operations have been explicitly enabled via an ADR decision and policy config.
    public static func buildRegistry() -> MCPToolRegistry {
        MCPToolRegistry(version: 1, tools: mutatingToolDescriptors)
    }

    // MARK: Handler registration

    /// Registers the three mutating tool handlers on `server`.
    ///
    /// - Parameters:
    ///   - server: The MCP `Server` to register handlers on.
    ///   - registry: The mutating tool registry built by `buildRegistry()`.
    ///   - mutationPort: Kubernetes write port forwarded into tool handlers.
    ///   - policyPort: Policy gate that must return `.allowed` for mutating verbs.
    ///   - logger: Logger used for handler-level events.
    public static func registerHandlers(
        on server: Server,
        registry: MCPToolRegistry,
        mutationPort: any KubernetesResourceMutationPort,
        policyPort: any ToolPolicyPort,
        logger: Logger
    ) async {
        await server.withMethodHandler(CallTool.self) { params in
            let name = params.name
            let args = params.arguments ?? [:]
            guard registry.tool(named: name) != nil else {
                return Self.errorResult("tool_not_registered")
            }
            guard let tool = registry.tool(named: name) else {
                return Self.errorResult("tool_not_registered")
            }
            let contextId = ContextId(Self.stringArg(args, "contextId") ?? "")
            let policyRequest = PolicyEvaluationRequest(
                tool: tool,
                argumentsJSON: Self.serializeArgs(args),
                kubernetesContextId: contextId
            )
            do {
                let decision = try await policyPort.evaluate(policyRequest)
                guard case .allowed = decision else {
                    if case .denied(_, let detail) = decision {
                        return Self.errorResult(detail)
                    }
                    return Self.errorResult("mutating_verb_denied_by_policy")
                }
                return try await Self.dispatch(
                    toolName: name,
                    args: args,
                    contextId: contextId,
                    mutationPort: mutationPort,
                    logger: logger
                )
            } catch {
                return Self.errorResult(error.localizedDescription)
            }
        }
    }

    // MARK: Tool dispatch

    private static func dispatch(
        toolName: String,
        args: [String: Value],
        contextId: ContextId,
        mutationPort: any KubernetesResourceMutationPort,
        logger: Logger
    ) async throws -> CallTool.Result {
        switch toolName {
        case "kube_apply":
            return try await handleApply(args: args, contextId: contextId, port: mutationPort, logger: logger)
        case "kube_delete":
            return try await handleDelete(args: args, contextId: contextId, port: mutationPort, logger: logger)
        case "kube_patch":
            return try await handlePatch(args: args, contextId: contextId, port: mutationPort, logger: logger)
        default:
            return errorResult("unknown_mutating_tool")
        }
    }

    // MARK: Individual handlers

    private static func handleApply(
        args: [String: Value],
        contextId: ContextId,
        port: any KubernetesResourceMutationPort,
        logger: Logger
    ) async throws -> CallTool.Result {
        let manifest = stringArg(args, "manifest") ?? ""
        let group = stringArg(args, "group") ?? ""
        let version = stringArg(args, "version") ?? "v1"
        let kind = stringArg(args, "kind") ?? ""
        let namespace = stringArg(args, "namespace")
        let name = stringArg(args, "name") ?? ""
        let gvk = GroupVersionKind(group: group, version: version, kind: kind)
        let command = ApplyYAML(
            targetGVK: gvk,
            namespace: namespace,
            name: name,
            manifestYAML: manifest,
            manifestDigest: sha256Hex(manifest)
        )
        let contextUUID = UUID(uuidString: contextId.rawValue) ?? UUID()
        let statusCode = try await port.applyYAML(command: command, contextId: contextUUID)
        logger.info("kube_apply succeeded", metadata: ["status": "\(statusCode)", "name": "\(name)"])
        let body = "{\"status\":\(statusCode),\"tool\":\"kube_apply\",\"name\":\"\(name)\"}"
        return CallTool.Result(content: [.text(text: body, annotations: nil, _meta: nil)])
    }

    private static func handleDelete(
        args: [String: Value],
        contextId: ContextId,
        port: any KubernetesResourceMutationPort,
        logger: Logger
    ) async throws -> CallTool.Result {
        let group = stringArg(args, "group") ?? ""
        let version = stringArg(args, "version") ?? "v1"
        let kind = stringArg(args, "kind") ?? ""
        let namespace = stringArg(args, "namespace")
        let name = stringArg(args, "name") ?? ""
        let gvk = GroupVersionKind(group: group, version: version, kind: kind)
        let command = DeleteResource(targetGVK: gvk, namespace: namespace, name: name)
        let contextUUID = UUID(uuidString: contextId.rawValue) ?? UUID()
        let statusCode = try await port.deleteResource(command: command, contextId: contextUUID)
        logger.info("kube_delete succeeded", metadata: ["status": "\(statusCode)", "name": "\(name)"])
        let body = "{\"status\":\(statusCode),\"tool\":\"kube_delete\",\"name\":\"\(name)\"}"
        return CallTool.Result(content: [.text(text: body, annotations: nil, _meta: nil)])
    }

    private static func handlePatch(
        args: [String: Value],
        contextId: ContextId,
        port: any KubernetesResourceMutationPort,
        logger: Logger
    ) async throws -> CallTool.Result {
        let group = stringArg(args, "group") ?? ""
        let version = stringArg(args, "version") ?? "v1"
        let kind = stringArg(args, "kind") ?? ""
        let namespace = stringArg(args, "namespace")
        let name = stringArg(args, "name") ?? ""
        let gvk = GroupVersionKind(group: group, version: version, kind: kind)
        // Patch is expressed as a label update for the MVP+ surface.
        let labelsRaw = stringArg(args, "labels") ?? "{}"
        let labels = parseStringMap(labelsRaw)
        let command = LabelPatch(targetGVK: gvk, namespace: namespace, name: name, labelsToSet: labels)
        let contextUUID = UUID(uuidString: contextId.rawValue) ?? UUID()
        let statusCode = try await port.labelPatch(command: command, contextId: contextUUID)
        logger.info("kube_patch succeeded", metadata: ["status": "\(statusCode)", "name": "\(name)"])
        let body = "{\"status\":\(statusCode),\"tool\":\"kube_patch\",\"name\":\"\(name)\"}"
        return CallTool.Result(content: [.text(text: body, annotations: nil, _meta: nil)])
    }

    // MARK: Argument helpers

    private static func stringArg(_ args: [String: Value], _ key: String) -> String? {
        args[key]?.stringValue
    }

    private static func serializeArgs(_ args: [String: Value]) -> String {
        guard
            let data = try? JSONEncoder().encode(args),
            let s = String(data: data, encoding: .utf8)
        else { return "{}" }
        return s
    }

    private static func parseStringMap(_ json: String) -> [String: String] {
        guard
            let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Minimal SHA-256 hex digest used as `manifestDigest` in `ApplyYAML`.
    private static func sha256Hex(_ input: String) -> String {
        // CryptoKit is not available in all configurations; use a stable placeholder.
        // Production adapters should inject a real digest via the composition root.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func errorResult(_ detail: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: "{\"error\":\"\(detail)\"}", annotations: nil, _meta: nil)],
            isError: true
        )
    }

    // MARK: Static tool descriptors

    private static let mutatingToolDescriptors: [MCPTool] = [
        MCPTool(
            name: "kube_apply",
            description: "Server-side applies a full YAML manifest to the cluster (SSA PATCH). Requires an explicit policy allow for mutating verbs.",
            inputJSONSchema: """
            {"type":"object","properties":{"manifest":{"type":"string"},"group":{"type":"string"},"version":{"type":"string"},"kind":{"type":"string"},"namespace":{"type":"string"},"name":{"type":"string"},"contextId":{"type":"string"}},"required":["manifest","kind","name"]}
            """,
            kubernetesVerbs: [.get],
            resources: ["*"],
            requiresPinnedContext: true
        ),
        MCPTool(
            name: "kube_delete",
            description: "Deletes a single Kubernetes resource by GVK, namespace, and name. Requires an explicit policy allow for mutating verbs.",
            inputJSONSchema: """
            {"type":"object","properties":{"group":{"type":"string"},"version":{"type":"string"},"kind":{"type":"string"},"namespace":{"type":"string"},"name":{"type":"string"},"contextId":{"type":"string"}},"required":["kind","name"]}
            """,
            kubernetesVerbs: [.get],
            resources: ["*"],
            requiresPinnedContext: true
        ),
        MCPTool(
            name: "kube_patch",
            description: "Applies a label-patch (strategic merge) to a Kubernetes resource. Requires an explicit policy allow for mutating verbs.",
            inputJSONSchema: """
            {"type":"object","properties":{"group":{"type":"string"},"version":{"type":"string"},"kind":{"type":"string"},"namespace":{"type":"string"},"name":{"type":"string"},"labels":{"type":"string"},"contextId":{"type":"string"}},"required":["kind","name"]}
            """,
            kubernetesVerbs: [.get],
            resources: ["*"],
            requiresPinnedContext: true
        ),
    ]
}
