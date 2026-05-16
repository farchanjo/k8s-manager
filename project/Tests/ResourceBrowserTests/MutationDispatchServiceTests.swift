// MutationDispatchServiceTests.swift — ResourceBrowserTests target
// Coverage: MutationDispatchService — token gate, audit recording, dispatch routing.
// ADR refs: ADR-0012 (confirmation-token gate, audit trail)

import XCTest
import Dependencies
@testable import ResourceBrowser
import SharedKernel

// MARK: - Fakes

private final class FakeMutationPort: KubernetesResourceMutationPort, @unchecked Sendable {
    var applyYAMLStatusCode = 200
    var shouldThrow = false

    func applyYAML(command: ApplyYAML, contextId: UUID) async throws -> Int {
        if shouldThrow { throw MutationError.transportError(detail: "network error") }
        return applyYAMLStatusCode
    }
    func scaleReplicas(command: ScaleReplicas, contextId: UUID) async throws -> Int { 200 }
    func rolloutRestart(command: RolloutRestart, contextId: UUID) async throws -> Int { 200 }
    func deleteResource(command: DeleteResource, contextId: UUID) async throws -> Int { 200 }
    func labelPatch(command: LabelPatch, contextId: UUID) async throws -> Int { 200 }
    func annotationPatch(command: AnnotationPatch, contextId: UUID) async throws -> Int { 200 }
}

private actor FakeAuditPort: MutationAuditPort {
    var recordedEntries: [MutationAuditEntry] = []
    var completedIds: [UUID] = []
    var shouldThrowDuplicate = false

    func setThrowDuplicate(_ value: Bool) {
        shouldThrowDuplicate = value
    }

    func record(_ entry: MutationAuditEntry) async throws {
        if shouldThrowDuplicate { throw AuditError.duplicateEntry(id: entry.id) }
        recordedEntries.append(entry)
    }

    func complete(id: UUID, outcome: MutationOutcome, completedAt: String, kubernetesStatusCode: Int?) async throws {
        completedIds.append(id)
    }

    func entries(contextId: UUID, limit: Int, offset: Int) async throws -> [MutationAuditEntry] { [] }
}

// MARK: - Helpers

private func makeScaleCommand() -> MutationCommand {
    .scaleReplicas(ScaleReplicas(
        targetGVK: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
        namespace: "default",
        name: "web",
        desiredReplicas: 3
    ))
}

private func makeApplyCommand() -> MutationCommand {
    .applyYAML(ApplyYAML(
        targetGVK: .core("ConfigMap"),
        namespace: "default",
        name: "cfg",
        manifestYAML: "a: b",
        manifestDigest: String(repeating: "0", count: 64)
    ))
}

// MARK: - Tests

final class MutationDispatchServiceTokenGateTests: XCTestCase {

    func test_dispatch_freshToken_succeeds() async throws {
        let mutPort = FakeMutationPort()
        let auditPort = FakeAuditPort()
        let contextId = UUID()

        let service = withDependencies {
            $0.kubernetesResourceMutation = mutPort
            $0.mutationAudit = auditPort
        } operation: {
            MutationDispatchService(config: MutationDispatchServiceConfig(
                kubernetesContextId: contextId
            ))
        }

        let result = try await service.dispatch(
            makeScaleCommand(),
            confirmationToken: UUID(),
            tokenIssuedAt: Date(),
            previousEntryDigest: MutationAuditEntry.genesisDigest
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.kubernetesStatusCode, 200)
    }

    func test_dispatch_expiredToken_throwsStale() async {
        let mutPort = FakeMutationPort()
        let auditPort = FakeAuditPort()

        let service = withDependencies {
            $0.kubernetesResourceMutation = mutPort
            $0.mutationAudit = auditPort
        } operation: {
            MutationDispatchService(config: MutationDispatchServiceConfig(
                kubernetesContextId: UUID(),
                maxConfirmationTokenAgeSeconds: 1
            ))
        }

        let staleDate = Date(timeIntervalSinceNow: -300) // 5 minutes ago
        do {
            _ = try await service.dispatch(
                makeScaleCommand(),
                confirmationToken: UUID(),
                tokenIssuedAt: staleDate,
                previousEntryDigest: MutationAuditEntry.genesisDigest
            )
            XCTFail("Expected staleConfirmationToken error")
        } catch MutationDispatchError.staleConfirmationToken(let age) {
            XCTAssertGreaterThan(age, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class MutationDispatchServiceAuditTests: XCTestCase {

    func test_dispatch_success_recordsAuditEntry() async throws {
        let mutPort = FakeMutationPort()
        let auditPort = FakeAuditPort()

        let service = withDependencies {
            $0.kubernetesResourceMutation = mutPort
            $0.mutationAudit = auditPort
        } operation: {
            MutationDispatchService(config: MutationDispatchServiceConfig(kubernetesContextId: UUID()))
        }

        _ = try await service.dispatch(
            makeApplyCommand(),
            confirmationToken: UUID(),
            tokenIssuedAt: Date(),
            previousEntryDigest: MutationAuditEntry.genesisDigest
        )

        let entries = await auditPort.recordedEntries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.outcome, .cancelled, "Pre-dispatch sentinel should be .cancelled")
    }

    func test_dispatch_apiError_completesAuditWithFailed() async throws {
        let mutPort = FakeMutationPort()
        mutPort.shouldThrow = true
        let auditPort = FakeAuditPort()

        let service = withDependencies {
            $0.kubernetesResourceMutation = mutPort
            $0.mutationAudit = auditPort
        } operation: {
            MutationDispatchService(config: MutationDispatchServiceConfig(kubernetesContextId: UUID()))
        }

        do {
            _ = try await service.dispatch(
                makeApplyCommand(),
                confirmationToken: UUID(),
                tokenIssuedAt: Date(),
                previousEntryDigest: MutationAuditEntry.genesisDigest
            )
            XCTFail("Expected apiError")
        } catch MutationDispatchError.apiError {
            let completed = await auditPort.completedIds
            XCTAssertEqual(completed.count, 1, "Audit entry should be completed with failed outcome")
        }
    }

    func test_dispatch_duplicateRequestId_throwsDuplicate() async throws {
        let mutPort = FakeMutationPort()
        let auditPort = FakeAuditPort()
        await auditPort.setThrowDuplicate(true)

        let service = withDependencies {
            $0.kubernetesResourceMutation = mutPort
            $0.mutationAudit = auditPort
        } operation: {
            MutationDispatchService(config: MutationDispatchServiceConfig(kubernetesContextId: UUID()))
        }

        do {
            _ = try await service.dispatch(
                makeApplyCommand(),
                confirmationToken: UUID(),
                tokenIssuedAt: Date(),
                previousEntryDigest: MutationAuditEntry.genesisDigest
            )
            XCTFail("Expected duplicateRequestId")
        } catch MutationDispatchError.duplicateRequestId {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
