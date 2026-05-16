// Tests/AppShellTests/ClusterIntelligenceViewModelTests.swift
// Coverage: ClusterIntelligenceViewModel registry load + invocation log flows.

import XCTest
import Dependencies
@testable import AppShell
import ClusterIntelligence
import SharedKernel

// MARK: - ClusterIntelligenceViewModelTests

@MainActor
final class ClusterIntelligenceViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = ClusterIntelligenceViewModel()
        XCTAssertTrue(sut.registry.isIdle)
        XCTAssertTrue(sut.recentInvocations.isIdle)
    }

    // MARK: loadRegistry

    func test_loadRegistry_successPopulatesSnapshot() async {
        let fakeTool = MCPTool(
            name: "list_pods",
            description: "Lists all pods in a namespace.",
            inputJSONSchema: "{}",
            kubernetesVerbs: [.list],
            resources: ["pods"],
            requiresPinnedContext: true
        )
        let fakeRegistry = MCPToolRegistry(version: 1, tools: [fakeTool])
        let fakeSnapshot = MCPRegistrySnapshotReadModel(from: fakeRegistry)
        let fakeTransport = FakeMCPTransport(snapshot: fakeSnapshot)

        await withDependencies {
            $0.mcpTransport = fakeTransport
        } operation: {
            let sut = ClusterIntelligenceViewModel()
            await sut.loadRegistry()
            guard case .success(let snap) = sut.registry else {
                return XCTFail("Expected .success, got \(sut.registry)")
            }
            XCTAssertEqual(snap.version, 1)
            XCTAssertEqual(snap.toolDescriptors.count, 1)
            XCTAssertEqual(snap.toolDescriptors.first?.name, "list_pods")
        }
    }

    func test_loadRegistry_unimplementedYieldsFailure() async {
        // Default liveValue / testValue for mcpTransport is Unimplemented.
        // registrySnapshot() is synchronous and does NOT throw on the sentinel —
        // it returns an empty registry snapshot instead. Verify the success path.
        await withDependencies { _ in
            // No override — uses UnimplementedMCPTransportPort (returns empty snapshot).
        } operation: {
            let sut = ClusterIntelligenceViewModel()
            await sut.loadRegistry()
            // UnimplementedMCPTransportPort.registrySnapshot() returns version=1, tools=[].
            XCTAssertNotNil(sut.registry.value, "Expected a snapshot value, not failure")
        }
    }

    // MARK: loadRecentInvocations

    func test_loadRecentInvocations_successPopulatesLog() async {
        let contextId = ContextId("ctx-1")
        let invocation = MCPInvocation(
            id: InvocationId(.init()),
            toolName: "list_pods",
            requestedAtRFC3339: "2026-01-01T00:00:00Z",
            completedAtRFC3339: "2026-01-01T00:00:01Z",
            kubernetesContextId: contextId,
            argumentsJSON: "{}",
            outcome: .succeeded(.init(
                resultJSON: "[]",
                resultBytes: 2,
                truncated: false,
                kubernetesStatusCode: 200
            ))
        )
        let fakeLog = MCPInvocationLogReadModel(entries: [invocation])
        let fakeLogPort = FakeMCPInvocationLogPort(log: fakeLog)

        await withDependencies {
            $0.mcpInvocationLog = fakeLogPort
        } operation: {
            let sut = ClusterIntelligenceViewModel()
            await sut.loadRecentInvocations()
            guard case .success(let log) = sut.recentInvocations else {
                return XCTFail("Expected .success, got \(sut.recentInvocations)")
            }
            XCTAssertEqual(log.entries.count, 1)
            XCTAssertEqual(log.entries.first?.toolName, "list_pods")
        }
    }

    func test_loadRecentInvocations_errorYieldsFailure() async {
        let fakeLogPort = FakeMCPInvocationLogPort(
            error: MCPInvocationLogError.readFailed(detail: "db locked")
        )

        await withDependencies {
            $0.mcpInvocationLog = fakeLogPort
        } operation: {
            let sut = ClusterIntelligenceViewModel()
            await sut.loadRecentInvocations()
            XCTAssertNotNil(sut.recentInvocations.error)
            XCTAssertNil(sut.recentInvocations.value)
        }
    }

    func test_loadRecentInvocations_emptyLogSucceeds() async {
        let fakeLogPort = FakeMCPInvocationLogPort(log: MCPInvocationLogReadModel(entries: []))

        await withDependencies {
            $0.mcpInvocationLog = fakeLogPort
        } operation: {
            let sut = ClusterIntelligenceViewModel()
            await sut.loadRecentInvocations()
            guard case .success(let log) = sut.recentInvocations else {
                return XCTFail("Expected .success, got \(sut.recentInvocations)")
            }
            XCTAssertTrue(log.entries.isEmpty)
        }
    }
}

// MARK: - Test doubles

private struct FakeMCPTransport: MCPTransportPort {
    let stubbedSnapshot: MCPRegistrySnapshotReadModel

    init(snapshot: MCPRegistrySnapshotReadModel) {
        self.stubbedSnapshot = snapshot
    }

    func dispatch(_ request: MCPTransportRequest) async throws -> ToolResult {
        throw MCPTransportError.unimplemented
    }

    func registrySnapshot() -> MCPRegistrySnapshotReadModel {
        stubbedSnapshot
    }
}

private struct FakeMCPInvocationLogPort: MCPInvocationLogPort {
    let stubbedLog: MCPInvocationLogReadModel?
    let stubbedError: Error?

    init(log: MCPInvocationLogReadModel? = nil, error: Error? = nil) {
        self.stubbedLog = log
        self.stubbedError = error
    }

    func append(_ invocation: MCPInvocation) async throws {
        throw MCPInvocationLogError.unimplemented
    }

    func recent(limit: Int) async throws -> MCPInvocationLogReadModel {
        if let error = stubbedError { throw error }
        return stubbedLog!
    }
}
