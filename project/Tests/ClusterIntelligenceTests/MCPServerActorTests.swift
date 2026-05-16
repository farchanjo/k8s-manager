// Tests/ClusterIntelligenceTests/MCPServerActorTests.swift
// XCTest coverage for MCPServerActor: dispatch, policy gate, audit, truncation, error paths.
// ADR ref: ADR-0009 §Confirmation — policy gate and audit assertions.

import XCTest
import Dependencies
@testable import ClusterIntelligence
import SharedKernel

// MARK: - MCPServerActorTests

final class MCPServerActorTests: XCTestCase {

    // MARK: Helpers

    private func makeTool(_ name: String, maxBytes: Int = 262_144) -> MCPTool {
        MCPTool(
            name: name,
            description: "Test \(name)",
            inputJSONSchema: "{}",
            kubernetesVerbs: [.get, .list],
            resources: ["pods"],
            requiresPinnedContext: true,
            outputMaxBytes: maxBytes
        )
    }

    private func makeRegistry(tools: [MCPTool]) -> MCPToolRegistry {
        MCPToolRegistry(version: 1, tools: tools)
    }

    private func makeCall(
        toolName: String,
        argsJSON: String = "{}",
        contextId: String = "ctx-test"
    ) -> MCPCallRequest {
        MCPCallRequest(
            toolName: toolName,
            argumentsJSON: argsJSON,
            kubernetesContextId: ContextId(contextId),
            requestedAtRFC3339: "2026-05-16T00:00:00Z"
        )
    }

    // MARK: Test 1 — unregistered tool throws

    func test_handle_throwsToolNotRegistered_whenToolAbsentFromRegistry() async throws {
        let actor = MCPServerActor(registry: makeRegistry(tools: []))
        let call = makeCall(toolName: "kube_delete_pod")

        do {
            _ = try await actor.handle(call: call)
            XCTFail("Expected MCPServerError.toolNotRegistered")
        } catch MCPServerError.toolNotRegistered(let name) {
            XCTAssertEqual(name, "kube_delete_pod")
        }
    }

    // MARK: Test 2 — policy denied produces deniedByPolicy outcome

    func test_handle_returnsDeniedByPolicy_whenPolicyDenies() async throws {
        let registry = makeRegistry(tools: [makeTool("kube_list_pods")])
        let actor = MCPServerActor(registry: registry)
        let call = makeCall(toolName: "kube_list_pods")

        let fakePolicy = FakeToolPolicyPort(
            decision: .denied(rule: "mutating_verb_forbidden", detail: "verb not allowed")
        )
        let fakeTransport = FakeMCPTransportPort(result: "{}")
        let fakeLog = SpyMCPInvocationLogPort()

        try await withDependencies {
            $0.toolPolicy = fakePolicy
            $0.mcpTransport = fakeTransport
            $0.mcpInvocationLog = fakeLog
        } operation: {
            let result = try await actor.handle(call: call)
            if case .deniedByPolicy(let payload) = result.invocation.outcome {
                XCTAssertEqual(payload.rule, "mutating_verb_forbidden")
            } else {
                XCTFail("Expected deniedByPolicy, got: \(result.invocation.outcome)")
            }
        }
    }

    // MARK: Test 3 — allowed call succeeds and appends to log

    func test_handle_succeeds_andAppendsToLog() async throws {
        let registry = makeRegistry(tools: [makeTool("kube_list_pods")])
        let actor = MCPServerActor(registry: registry)
        let call = makeCall(toolName: "kube_list_pods")

        let fakePolicy = FakeToolPolicyPort(decision: .allowed)
        let fakeTransport = FakeMCPTransportPort(result: "{\"pods\":[]}")
        let spyLog = SpyMCPInvocationLogPort()

        try await withDependencies {
            $0.toolPolicy = fakePolicy
            $0.mcpTransport = fakeTransport
            $0.mcpInvocationLog = spyLog
        } operation: {
            let result = try await actor.handle(call: call)
            XCTAssertFalse(result.resultJSON.isEmpty)
            if case .succeeded(let payload) = result.invocation.outcome {
                XCTAssertFalse(payload.truncated)
            } else {
                XCTFail("Expected succeeded outcome")
            }
            XCTAssertEqual(spyLog.appendedCount, 1)
        }
    }

    // MARK: Test 4 — result truncation at configured maxBytes

    func test_handle_truncatesResult_whenExceedsOutputMaxBytes() async throws {
        let tinyTool = makeTool("kube_list_pods", maxBytes: 60)
        let registry = makeRegistry(tools: [tinyTool])
        let actor = MCPServerActor(registry: registry)
        let call = makeCall(toolName: "kube_list_pods")

        let largeJSON = "{\"pods\":\(String(repeating: "\"pod\"", count: 20))}"
        let fakePolicy = FakeToolPolicyPort(decision: .allowed)
        let fakeTransport = FakeMCPTransportPort(result: largeJSON)
        let spyLog = SpyMCPInvocationLogPort()

        try await withDependencies {
            $0.toolPolicy = fakePolicy
            $0.mcpTransport = fakeTransport
            $0.mcpInvocationLog = spyLog
        } operation: {
            let result = try await actor.handle(call: call)
            XCTAssertTrue(result.truncated)
            XCTAssertTrue(TruncationMarker.isTruncated(result.resultJSON))
            XCTAssertLessThanOrEqual(result.resultJSON.utf8.count, tinyTool.outputMaxBytes)
        }
    }

    // MARK: Test 5 — registrySnapshot returns the registry passed at init

    func test_registrySnapshot_returnsInjectedRegistry() async {
        let tools = [makeTool("kube_describe"), makeTool("kube_logs")]
        let registry = makeRegistry(tools: tools)
        let actor = MCPServerActor(registry: registry)

        let snapshot = await actor.registrySnapshot()
        XCTAssertEqual(snapshot.version, 1)
        XCTAssertEqual(snapshot.tools.count, 2)
    }

    // MARK: Test 6 — policy engine failure propagates as MCPServerError

    func test_handle_throwsPolicyEngineFailed_whenPolicyPortThrows() async throws {
        let registry = makeRegistry(tools: [makeTool("kube_events")])
        let actor = MCPServerActor(registry: registry)
        let call = makeCall(toolName: "kube_events")

        let throwingPolicy = ThrowingToolPolicyPort()
        let fakeTransport = FakeMCPTransportPort(result: "{}")
        let spyLog = SpyMCPInvocationLogPort()

        do {
            try await withDependencies {
                $0.toolPolicy = throwingPolicy
                $0.mcpTransport = fakeTransport
                $0.mcpInvocationLog = spyLog
            } operation: {
                _ = try await actor.handle(call: call)
                XCTFail("Expected MCPServerError.policyEngineFailed")
            }
        } catch MCPServerError.policyEngineFailed {
            // expected path
        }
    }
}

// MARK: - Test doubles

private struct FakeToolPolicyPort: ToolPolicyPort {
    let decision: PolicyDecision
    func evaluate(_ request: PolicyEvaluationRequest) async throws -> PolicyDecision { decision }
}

private struct ThrowingToolPolicyPort: ToolPolicyPort {
    func evaluate(_ request: PolicyEvaluationRequest) async throws -> PolicyDecision {
        throw ToolPolicyError.evaluationFailed(detail: "engine crashed")
    }
}

private struct FakeMCPTransportPort: MCPTransportPort {
    let result: String

    func dispatch(_ request: MCPTransportRequest) async throws -> ToolResult {
        let outcome = MCPOutcome.succeeded(.init(
            resultJSON: result,
            resultBytes: result.utf8.count,
            truncated: false,
            kubernetesStatusCode: 200
        ))
        let invocation = MCPInvocation(
            id: .generate(),
            toolName: request.toolName,
            requestedAtRFC3339: request.requestedAtRFC3339,
            kubernetesContextId: request.kubernetesContextId,
            argumentsJSON: request.argumentsJSON,
            outcome: outcome
        )
        return ToolResult(resultJSON: result, truncated: false, invocation: invocation)
    }

    func registrySnapshot() -> MCPRegistrySnapshotReadModel {
        MCPRegistrySnapshotReadModel(from: MCPToolRegistry(version: 1, tools: []))
    }
}

private final class SpyMCPInvocationLogPort: MCPInvocationLogPort, @unchecked Sendable {
    private(set) var appendedCount = 0

    func append(_ invocation: MCPInvocation) async throws {
        appendedCount += 1
    }

    func recent(limit: Int) async throws -> MCPInvocationLogReadModel {
        MCPInvocationLogReadModel(entries: [])
    }
}
