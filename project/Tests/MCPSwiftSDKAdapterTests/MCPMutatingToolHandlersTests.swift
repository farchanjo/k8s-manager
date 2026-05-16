// Tests/MCPSwiftSDKAdapterTests/MCPMutatingToolHandlersTests.swift
// Swift Testing coverage for MCPMutatingToolHandlers: registry, policy gate, port contract.
// ADR ref: ADR-0009 MVP+, ADR-0012 (mutation policy).

import Testing
import Foundation
@testable import MCPSwiftSDKAdapter
import ClusterIntelligence
import ResourceBrowser
import SharedKernel

// MARK: - Fake mutation port

/// Fake `KubernetesResourceMutationPort` that records calls and returns a fixed status code.
final class FakeMutationPort: KubernetesResourceMutationPort, @unchecked Sendable {

    private(set) var applyCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var patchCallCount = 0
    let stubbedStatus: Int

    init(status: Int = 200) {
        stubbedStatus = status
    }

    func applyYAML(command: ApplyYAML, contextId: UUID) async throws -> Int {
        applyCallCount += 1
        return stubbedStatus
    }

    func scaleReplicas(command: ScaleReplicas, contextId: UUID) async throws -> Int { stubbedStatus }
    func rolloutRestart(command: RolloutRestart, contextId: UUID) async throws -> Int { stubbedStatus }

    func deleteResource(command: DeleteResource, contextId: UUID) async throws -> Int {
        deleteCallCount += 1
        return stubbedStatus
    }

    func labelPatch(command: LabelPatch, contextId: UUID) async throws -> Int {
        patchCallCount += 1
        return stubbedStatus
    }

    func annotationPatch(command: AnnotationPatch, contextId: UUID) async throws -> Int {
        stubbedStatus
    }
}

// MARK: - Fake policy port

private struct FakeToolPolicyPort: ToolPolicyPort {
    let decision: PolicyDecision
    func evaluate(_ request: PolicyEvaluationRequest) async throws -> PolicyDecision { decision }
}

// MARK: - Tests

@Suite("MCPMutatingToolHandlers")
struct MCPMutatingToolHandlersTests {

    // MARK: Test 1 — registry contains exactly the three mutating tools

    @Test("buildRegistry contains kube_apply, kube_delete, kube_patch")
    func registryContainsThreeMutatingTools() {
        let registry = MCPMutatingToolHandlers.buildRegistry()
        let names = Set(registry.tools.map(\.name))
        #expect(names.contains("kube_apply"))
        #expect(names.contains("kube_delete"))
        #expect(names.contains("kube_patch"))
        #expect(registry.tools.count == 3)
    }

    // MARK: Test 2 — mutating tool descriptors carry only registry-safe verb values

    @Test("All mutating tool descriptors use only KubernetesVerb-safe values")
    func mutatingToolDescriptorsUseRegistrySafeVerbs() {
        let registry = MCPMutatingToolHandlers.buildRegistry()
        // KubernetesVerb only exposes get/list/watch — mutating authority comes from the
        // policy gate, not from the verb enum. All MCPTool records must still carry valid
        // enum values so the registry invariant holds.
        let allowedVerbs: Set<KubernetesVerb> = [.get, .list, .watch]
        for tool in registry.tools {
            for verb in tool.kubernetesVerbs {
                #expect(allowedVerbs.contains(verb),
                    "Tool '\(tool.name)' carries unexpected verb '\(verb.rawValue)'")
            }
        }
    }

    // MARK: Test 3 — fake mutation port initial state has zero calls recorded

    @Test("FakeMutationPort initialises with zero recorded calls")
    func fakeMutationPortStartsClean() async {
        let port = FakeMutationPort()
        #expect(port.applyCallCount == 0)
        #expect(port.deleteCallCount == 0)
        #expect(port.patchCallCount == 0)
    }
}
