// MCPSwiftSDKAdapterTests.swift — MCPSwiftSDKAdapterTests target
// Tests: MCPInProcessTransport + MCPToolHandlers with a fake KubernetesResourceListPort
// ADR ref: ADR-0009 §Confirmation — tool dispatch shape assertions

import Testing
import Foundation
@testable import MCPSwiftSDKAdapter
import ClusterIntelligence
import ResourceBrowser
import SharedKernel

// MARK: - Fake port

/// Fake `KubernetesResourceListPort` that returns deterministic test fixtures.
private struct FakeKubernetesResourceListPort: KubernetesResourceListPort {

    func list(
        gvk: GroupVersionKind,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> [ResourceListItem] {
        [
            ResourceListItem(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                gvk: gvk,
                namespace: namespace ?? "default",
                name: "test-pod",
                uid: "uid-1",
                creationTimestamp: "2026-01-01T00:00:00Z",
                status: "Running",
                ageSeconds: 3600
            ),
        ]
    }

    func get(
        gvk: GroupVersionKind,
        name: String,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> ResourceDetail {
        let item = ResourceListItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            gvk: gvk,
            namespace: namespace ?? "default",
            name: name,
            uid: "uid-2",
            creationTimestamp: "2026-01-01T00:00:00Z",
            status: "Running",
            ageSeconds: 60
        )
        return ResourceDetail(listItem: item, rawJSON: "{\"name\":\"\(name)\"}")
    }
}

// MARK: - Tests

@Suite("MCPSwiftSDKAdapter")
struct MCPSwiftSDKAdapterTests {

    // MARK: Registry

    @Test("buildRegistry contains all six curated tools")
    func registryContainsSixTools() {
        let registry = MCPToolHandlers.buildRegistry()
        let names = registry.tools.map(\.name)
        let expected = [
            "kube_get_pod",
            "kube_list_pods",
            "kube_list_deployments",
            "kube_get_service",
            "kube_get_namespace",
            "kube_list_events",
        ]
        for name in expected {
            #expect(names.contains(name), "Registry missing tool: \(name)")
        }
        #expect(registry.tools.count == 6)
    }

    @Test("All registry tools carry only read-only Kubernetes verbs")
    func registryToolsAreReadOnly() {
        let registry = MCPToolHandlers.buildRegistry()
        let allowedVerbs: Set<KubernetesVerb> = [.get, .list, .watch]
        for tool in registry.tools {
            for verb in tool.kubernetesVerbs {
                #expect(allowedVerbs.contains(verb),
                    "Tool '\(tool.name)' has mutating verb '\(verb.rawValue)'")
            }
        }
    }

    @Test("registrySnapshot version matches registry version")
    func registrySnapshotVersion() async throws {
        let transport = try await MCPInProcessTransport(
            resourceListPort: FakeKubernetesResourceListPort()
        )
        let snapshot = transport.registrySnapshot()
        #expect(snapshot.version == 1)
        #expect(snapshot.toolDescriptors.count == 6)
    }

    // MARK: Dispatch — known tools

    @Test("dispatch kube_list_pods returns succeeded outcome with JSON body")
    func dispatchListPodsSucceeds() async throws {
        let transport = try await MCPInProcessTransport(
            resourceListPort: FakeKubernetesResourceListPort()
        )
        let request = MCPTransportRequest(
            toolName: "kube_list_pods",
            argumentsJSON: "{\"namespace\":\"default\"}",
            kubernetesContextId: ContextId("test-context"),
            requestedAtRFC3339: "2026-01-01T00:00:00Z"
        )
        let result = try await transport.dispatch(request)

        #expect(!result.resultJSON.isEmpty)
        if case .succeeded(let payload) = result.invocation.outcome {
            #expect(payload.kubernetesStatusCode == 200)
            #expect(!payload.resultJSON.isEmpty)
        } else {
            Issue.record("Expected succeeded outcome, got: \(result.invocation.outcome)")
        }
    }

    @Test("dispatch kube_get_pod returns rawJSON from fake port")
    func dispatchGetPodReturnsRawJSON() async throws {
        let transport = try await MCPInProcessTransport(
            resourceListPort: FakeKubernetesResourceListPort()
        )
        let request = MCPTransportRequest(
            toolName: "kube_get_pod",
            argumentsJSON: "{\"name\":\"my-pod\",\"namespace\":\"default\"}",
            kubernetesContextId: ContextId("test-context"),
            requestedAtRFC3339: "2026-01-01T00:00:00Z"
        )
        let result = try await transport.dispatch(request)
        #expect(result.resultJSON.contains("my-pod"))
    }

    // MARK: Dispatch — unknown tool

    @Test("dispatch unknown tool returns deniedByPolicy outcome")
    func dispatchUnknownToolDenied() async throws {
        let transport = try await MCPInProcessTransport(
            resourceListPort: FakeKubernetesResourceListPort()
        )
        let request = MCPTransportRequest(
            toolName: "kube_delete_pod",
            argumentsJSON: "{}",
            kubernetesContextId: ContextId("test-context"),
            requestedAtRFC3339: "2026-01-01T00:00:00Z"
        )
        let result = try await transport.dispatch(request)

        if case .deniedByPolicy(let payload) = result.invocation.outcome {
            #expect(payload.rule == "tool_not_registered")
        } else {
            Issue.record("Expected deniedByPolicy, got: \(result.invocation.outcome)")
        }
    }

    // MARK: Module accessibility

    @Test("MCPSwiftSDKAdapter module is accessible")
    func moduleAccessible() {
        // Verifies the module marker type is reachable from the test target.
        let version = MCPSwiftSDKAdapter.moduleVersion
        #expect(!version.isEmpty)
    }
}
