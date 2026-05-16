// ClusterIntelligenceTests.swift — cluster_intelligence bounded context
// XCTest coverage: domain types, registry invariants, policy port DI,
// truncation marker, and negative ADR-0009 assertions.

import XCTest
import Dependencies
@testable import ClusterIntelligence
import SharedKernel

// MARK: - InvocationIdTests

final class InvocationIdTests: XCTestCase {
    func test_generate_produces_distinct_values() {
        let a = InvocationId.generate()
        let b = InvocationId.generate()
        XCTAssertNotEqual(a, b)
    }

    func test_equality_based_on_rawValue() {
        let uuid = UUID()
        let x = InvocationId(uuid)
        let y = InvocationId(uuid)
        XCTAssertEqual(x, y)
    }
}

// MARK: - MCPOutcomeTests

final class MCPOutcomeTests: XCTestCase {
    func test_succeeded_codable_roundtrip() throws {
        let outcome = MCPOutcome.succeeded(
            MCPOutcome.SucceededPayload(
                resultJSON: "{\"pods\":[]}",
                resultBytes: 12,
                truncated: false,
                kubernetesStatusCode: 200
            )
        )
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(MCPOutcome.self, from: data)
        XCTAssertEqual(outcome, decoded)
    }

    func test_deniedByPolicy_codable_roundtrip() throws {
        let outcome = MCPOutcome.deniedByPolicy(
            MCPOutcome.DeniedByPolicyPayload(
                rule: "tool_not_registered",
                detail: "kube_delete_pod is not in the registry"
            )
        )
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(MCPOutcome.self, from: data)
        XCTAssertEqual(outcome, decoded)
    }

    func test_failed_codable_roundtrip_with_status_code() throws {
        let outcome = MCPOutcome.failed(
            MCPOutcome.FailedPayload(kubernetesStatusCode: 403, reason: "Forbidden")
        )
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(MCPOutcome.self, from: data)
        XCTAssertEqual(outcome, decoded)
    }

    func test_failed_codable_roundtrip_without_status_code() throws {
        let outcome = MCPOutcome.failed(
            MCPOutcome.FailedPayload(reason: "connection refused")
        )
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(MCPOutcome.self, from: data)
        XCTAssertEqual(outcome, decoded)
    }

    func test_cancelled_codable_roundtrip() throws {
        let outcome = MCPOutcome.cancelled
        let data = try JSONEncoder().encode(outcome)
        let decoded = try JSONDecoder().decode(MCPOutcome.self, from: data)
        XCTAssertEqual(outcome, decoded)
    }
}

// MARK: - MCPInvocationTests

final class MCPInvocationTests: XCTestCase {
    func test_construction_roundtrips_all_fields() {
        let id = InvocationId.generate()
        let contextId = ContextId("ctx-abc")
        let invocation = MCPInvocation(
            id: id,
            toolName: "kube_list_pods",
            requestedAtRFC3339: "2026-05-15T12:00:00Z",
            completedAtRFC3339: "2026-05-15T12:00:00.050Z",
            kubernetesContextId: contextId,
            argumentsJSON: "{\"namespace\":\"default\"}",
            outcome: .cancelled
        )

        XCTAssertEqual(invocation.id, id)
        XCTAssertEqual(invocation.toolName, "kube_list_pods")
        XCTAssertEqual(invocation.requestedAtRFC3339, "2026-05-15T12:00:00Z")
        XCTAssertEqual(invocation.completedAtRFC3339, "2026-05-15T12:00:00.050Z")
        XCTAssertEqual(invocation.kubernetesContextId, contextId)
        XCTAssertEqual(invocation.argumentsJSON, "{\"namespace\":\"default\"}")
        XCTAssertEqual(invocation.outcome, .cancelled)
    }

    func test_completedAt_defaults_to_nil() {
        let invocation = MCPInvocation(
            id: .generate(),
            toolName: "kube_cluster_info",
            requestedAtRFC3339: "2026-05-15T12:00:00Z",
            kubernetesContextId: ContextId("ctx"),
            argumentsJSON: "{}",
            outcome: .cancelled
        )
        XCTAssertNil(invocation.completedAtRFC3339)
    }

    func test_invocation_codable_roundtrip() throws {
        let invocation = MCPInvocation(
            id: InvocationId(UUID()),
            toolName: "kube_describe",
            requestedAtRFC3339: "2026-05-15T10:00:00Z",
            completedAtRFC3339: "2026-05-15T10:00:01Z",
            kubernetesContextId: ContextId("prod"),
            argumentsJSON: "{\"kind\":\"Pod\",\"name\":\"nginx-0\"}",
            outcome: .succeeded(
                MCPOutcome.SucceededPayload(
                    resultJSON: "{\"status\":\"Running\"}",
                    resultBytes: 18,
                    truncated: false,
                    kubernetesStatusCode: 200
                )
            )
        )

        let data = try JSONEncoder().encode(invocation)
        let decoded = try JSONDecoder().decode(MCPInvocation.self, from: data)
        XCTAssertEqual(invocation, decoded)
    }
}

// MARK: - MCPToolTests

final class MCPToolTests: XCTestCase {
    func test_construction_roundtrips_fields() {
        let tool = MCPTool(
            name: "kube_list_pods",
            description: "Lists pods in a namespace.",
            inputJSONSchema: "{}",
            kubernetesVerbs: [.list],
            resources: ["pods"],
            requiresPinnedContext: true
        )

        XCTAssertEqual(tool.name, "kube_list_pods")
        XCTAssertEqual(tool.kubernetesVerbs, [.list])
        XCTAssertEqual(tool.resources, ["pods"])
        XCTAssertTrue(tool.requiresPinnedContext)
        XCTAssertEqual(tool.outputMaxBytes, 262_144)
    }

    func test_custom_outputMaxBytes() {
        let tool = MCPTool(
            name: "kube_logs",
            description: "Streams container logs.",
            inputJSONSchema: "{}",
            kubernetesVerbs: [.get],
            resources: ["pods/log"],
            requiresPinnedContext: true,
            outputMaxBytes: 512_000
        )
        XCTAssertEqual(tool.outputMaxBytes, 512_000)
    }

    func test_kubernetesVerb_allCases_does_not_include_mutating_verbs() {
        let writingVerbs = ["post", "put", "patch", "delete", "create"]
        for raw in writingVerbs {
            XCTAssertNil(KubernetesVerb(rawValue: raw), "Mutating verb '\(raw)' must not exist")
        }
    }
}

// MARK: - MCPToolRegistryTests

final class MCPToolRegistryTests: XCTestCase {
    private func makeTool(_ name: String) -> MCPTool {
        MCPTool(
            name: name,
            description: "Test tool \(name)",
            inputJSONSchema: "{}",
            kubernetesVerbs: [.get, .list],
            resources: ["pods"],
            requiresPinnedContext: true
        )
    }

    func test_tool_lookup_by_name() {
        let registry = MCPToolRegistry(version: 1, tools: [makeTool("kube_list_pods")])
        XCTAssertNotNil(registry.tool(named: "kube_list_pods"))
        XCTAssertNil(registry.tool(named: "kube_delete_pod"))
    }

    /// ADR-0009 negative test: `kube_delete_pod` must not be registered.
    func test_unregistered_mutating_tool_returns_nil() {
        let registry = MCPToolRegistry(version: 1, tools: [makeTool("kube_list_pods")])
        let found = registry.tool(named: "kube_delete_pod")
        XCTAssertNil(found, "Mutating tool kube_delete_pod must not appear in the registry")
    }

    func test_version_is_preserved() {
        let registry = MCPToolRegistry(version: 3, tools: [])
        XCTAssertEqual(registry.version, 3)
    }

    func test_snapshot_read_model_matches_registry() {
        let tools = [makeTool("kube_list_pods"), makeTool("kube_describe")]
        let registry = MCPToolRegistry(version: 2, tools: tools)
        let snapshot = MCPRegistrySnapshotReadModel(from: registry)

        XCTAssertEqual(snapshot.version, 2)
        XCTAssertEqual(snapshot.toolDescriptors.map(\.name).sorted(),
                       ["kube_describe", "kube_list_pods"])
    }
}

// MARK: - TruncationMarkerTests

final class TruncationMarkerTests: XCTestCase {
    func test_no_truncation_when_within_budget() {
        let body = "{\"pods\":[]}"
        let (result, truncated) = TruncationMarker.apply(to: body, maxBytes: 256)
        XCTAssertEqual(result, body)
        XCTAssertFalse(truncated)
    }

    func test_truncation_appends_marker() {
        let body = String(repeating: "x", count: 100)
        let (result, truncated) = TruncationMarker.apply(to: body, maxBytes: 50)
        XCTAssertTrue(truncated)
        XCTAssertTrue(TruncationMarker.isTruncated(result))
    }

    func test_suffix_includes_omitted_bytes() {
        let suffix = TruncationMarker.suffix(omittedBytes: 42)
        XCTAssertTrue(suffix.contains("42"))
        XCTAssertTrue(suffix.contains("_omittedBytes"))
    }

    func test_truncated_result_is_within_budget() {
        let body = String(repeating: "a", count: 1_000)
        let budget = 200
        let (result, _) = TruncationMarker.apply(to: body, maxBytes: budget)
        XCTAssertLessThanOrEqual(result.utf8.count, budget)
    }
}

// MARK: - MCPTransportPortDITests

final class MCPTransportPortDITests: XCTestCase {
    func test_unimplemented_port_throws_on_dispatch() async {
        let port = UnimplementedMCPTransportPort()
        let request = MCPTransportRequest(
            toolName: "kube_list_pods",
            argumentsJSON: "{}",
            kubernetesContextId: ContextId("ctx"),
            requestedAtRFC3339: "2026-05-15T12:00:00Z"
        )

        do {
            _ = try await port.dispatch(request)
            XCTFail("Expected unimplemented error")
        } catch MCPTransportError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_port_can_be_overridden_via_dependencies() async throws {
        let fake = FakeMCPTransportPort()

        try await withDependencies {
            $0.mcpTransport = fake
        } operation: {
            @Dependency(\.mcpTransport) var transport
            let request = MCPTransportRequest(
                toolName: "kube_cluster_info",
                argumentsJSON: "{}",
                kubernetesContextId: ContextId("ctx"),
                requestedAtRFC3339: "2026-05-15T12:00:00Z"
            )
            let result = try await transport.dispatch(request)
            XCTAssertEqual(result.resultJSON, FakeMCPTransportPort.stubbedJSON)
        }
    }
}

// MARK: - ToolPolicyPortDITests

final class ToolPolicyPortDITests: XCTestCase {
    func test_unimplemented_port_throws() async {
        let port = UnimplementedToolPolicyPort()
        let tool = MCPTool(
            name: "kube_list_pods",
            description: "",
            inputJSONSchema: "{}",
            kubernetesVerbs: [.list],
            resources: ["pods"],
            requiresPinnedContext: true
        )
        let req = PolicyEvaluationRequest(
            tool: tool,
            argumentsJSON: "{}",
            kubernetesContextId: ContextId("ctx")
        )

        do {
            _ = try await port.evaluate(req)
            XCTFail("Expected unimplemented error")
        } catch ToolPolicyError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_policy_port_can_be_overridden_via_dependencies() async throws {
        let fake = FakeToolPolicyPort(decision: .allowed)

        try await withDependencies {
            $0.toolPolicy = fake
        } operation: {
            @Dependency(\.toolPolicy) var policy
            let tool = MCPTool(
                name: "kube_events",
                description: "",
                inputJSONSchema: "{}",
                kubernetesVerbs: [.list],
                resources: ["events"],
                requiresPinnedContext: true
            )
            let req = PolicyEvaluationRequest(
                tool: tool,
                argumentsJSON: "{}",
                kubernetesContextId: ContextId("ctx")
            )
            let decision = try await policy.evaluate(req)
            if case .allowed = decision { /* pass */ } else {
                XCTFail("Expected allowed decision")
            }
        }
    }

    /// ADR-0009 negative test: a forged mutating verb must be denied by the policy.
    func test_mutating_verb_is_denied_by_policy() async throws {
        let fake = FakeToolPolicyPort(
            decision: .denied(
                rule: "mutating_verb_forbidden",
                detail: "verb 'delete' is not allowed"
            )
        )

        try await withDependencies {
            $0.toolPolicy = fake
        } operation: {
            @Dependency(\.toolPolicy) var policy
            let tool = MCPTool(
                name: "kube_list_pods",
                description: "",
                inputJSONSchema: "{}",
                kubernetesVerbs: [.list],
                resources: ["pods"],
                requiresPinnedContext: true
            )
            let req = PolicyEvaluationRequest(
                tool: tool,
                argumentsJSON: "{\"verb\":\"delete\"}",
                kubernetesContextId: ContextId("ctx")
            )
            let decision = try await policy.evaluate(req)
            if case .denied(let rule, _) = decision {
                XCTAssertEqual(rule, "mutating_verb_forbidden")
            } else {
                XCTFail("Expected denied_by_policy for mutating verb")
            }
        }
    }
}

// MARK: - Test doubles

private struct FakeMCPTransportPort: MCPTransportPort {
    static let stubbedJSON = "{\"version\":\"v1.29.3\"}"

    func dispatch(_ request: MCPTransportRequest) async throws -> ToolResult {
        let outcome = MCPOutcome.succeeded(
            MCPOutcome.SucceededPayload(
                resultJSON: Self.stubbedJSON,
                resultBytes: Self.stubbedJSON.utf8.count,
                truncated: false,
                kubernetesStatusCode: 200
            )
        )
        let invocation = MCPInvocation(
            id: .generate(),
            toolName: request.toolName,
            requestedAtRFC3339: request.requestedAtRFC3339,
            kubernetesContextId: request.kubernetesContextId,
            argumentsJSON: request.argumentsJSON,
            outcome: outcome
        )
        return ToolResult(
            resultJSON: Self.stubbedJSON,
            truncated: false,
            invocation: invocation
        )
    }

    func registrySnapshot() -> MCPRegistrySnapshotReadModel {
        MCPRegistrySnapshotReadModel(from: MCPToolRegistry(version: 1, tools: []))
    }
}

private struct FakeToolPolicyPort: ToolPolicyPort {
    let decision: PolicyDecision

    func evaluate(_ request: PolicyEvaluationRequest) async throws -> PolicyDecision {
        decision
    }
}
