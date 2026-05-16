// Tests/AppShellTests/ClusterOperations/ApplyYAMLViewModelTests.swift
// Coverage: ApplyYAMLViewModel — validation, dry-run vs apply, namespace override, file drop.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - ApplyYAMLViewModelTests

@MainActor
final class ApplyYAMLViewModelTests: XCTestCase {

    private let clusterId = ClusterId("test-cluster")

    // MARK: Initial state

    func test_initialState() {
        let sut = makeSUT()
        XCTAssertTrue(sut.yamlText.isEmpty)
        XCTAssertFalse(sut.dryRun)
        XCTAssertNil(sut.namespaceOverride)
        XCTAssertTrue(sut.applyState.isIdle)
        XCTAssertTrue(sut.validationErrors.isEmpty)
    }

    // MARK: Validation

    func test_validate_emptyTextProducesNoErrors() async {
        let sut = makeSUT()
        sut.yamlText = ""
        await sut.validate()
        XCTAssertTrue(sut.validationErrors.isEmpty)
    }

    func test_validate_missingApiVersionProducesError() async {
        let sut = makeSUT()
        sut.yamlText = "kind: Pod\nmetadata:\n  name: test\n"
        await sut.validate()
        let apiVersionErrors = sut.validationErrors.filter { $0.message.contains("apiVersion") }
        XCTAssertFalse(apiVersionErrors.isEmpty)
        XCTAssertEqual(apiVersionErrors.first?.severity, .error)
    }

    func test_validate_missingKindProducesError() async {
        let sut = makeSUT()
        sut.yamlText = "apiVersion: v1\nmetadata:\n  name: test\n"
        await sut.validate()
        let kindErrors = sut.validationErrors.filter { $0.message.contains("kind") }
        XCTAssertFalse(kindErrors.isEmpty)
    }

    func test_validate_validManifestProducesNoBlockingErrors() async {
        let sut = makeSUT()
        sut.yamlText = validYAML()
        await sut.validate()
        let blocking = sut.validationErrors.filter { $0.severity == .error }
        XCTAssertTrue(blocking.isEmpty)
    }

    // MARK: Apply — dry-run vs real apply

    func test_apply_withValidManifestAndDryRunTrue_setsDryRunResult() async throws {
        let stub = SucceedingMutationPort()
        try await withDependencies {
            $0.kubernetesResourceMutation = stub
        } operation: {
            let sut = makeSUT()
            sut.yamlText = validYAML()
            sut.dryRun = true
            await sut.apply(clusterId: clusterId)
            let result = try XCTUnwrap(sut.applyState.value)
            XCTAssertTrue(result.dryRun)
            XCTAssertNotNil(result.managedFieldsDiff)
        }
    }

    func test_apply_withValidManifestAndDryRunFalse_setsNonDryRunResult() async throws {
        let stub = SucceedingMutationPort()
        try await withDependencies {
            $0.kubernetesResourceMutation = stub
        } operation: {
            let sut = makeSUT()
            sut.yamlText = validYAML()
            sut.dryRun = false
            await sut.apply(clusterId: clusterId)
            let result = try XCTUnwrap(sut.applyState.value)
            XCTAssertFalse(result.dryRun)
            XCTAssertNil(result.managedFieldsDiff)
        }
    }

    func test_apply_withValidManifestAndDryRunFalse_clearsYamlText() async throws {
        let stub = SucceedingMutationPort()
        try await withDependencies {
            $0.kubernetesResourceMutation = stub
        } operation: {
            let sut = makeSUT()
            sut.yamlText = validYAML()
            sut.dryRun = false
            await sut.apply(clusterId: clusterId)
            XCTAssertTrue(sut.yamlText.isEmpty)
        }
    }

    func test_apply_blockedByValidationErrors_doesNotCallPort() async throws {
        let spy = SpyMutationPort()
        try await withDependencies {
            $0.kubernetesResourceMutation = spy
        } operation: {
            let sut = makeSUT()
            sut.yamlText = "kind: Pod\nmetadata:\n  name: test\n"  // missing apiVersion
            await sut.apply(clusterId: clusterId)
            XCTAssertEqual(spy.callCount, 0)
            XCTAssertTrue(sut.applyState.isIdle)
        }
    }

    // MARK: Namespace override

    func test_namespaceOverride_isUsedWhenSet() async throws {
        let spy = SpyMutationPort()
        try await withDependencies {
            $0.kubernetesResourceMutation = spy
        } operation: {
            let sut = makeSUT()
            sut.yamlText = validYAML()
            sut.namespaceOverride = "production"
            await sut.apply(clusterId: clusterId)
            XCTAssertEqual(spy.lastNamespace, "production")
        }
    }

    // MARK: File drop

    func test_dropFile_loadsContentIntoYamlText() async throws {
        let sut = makeSUT()
        let tempURL = try writeTemp(content: validYAML())
        await sut.dropFile(at: tempURL)
        XCTAssertFalse(sut.yamlText.isEmpty)
        XCTAssertTrue(sut.yamlText.contains("apiVersion"))
    }

    func test_dropFile_withInvalidURL_setsValidationError() async {
        let sut = makeSUT()
        let badURL = URL(fileURLWithPath: "/nonexistent/path/manifest.yaml")
        await sut.dropFile(at: badURL)
        XCTAssertFalse(sut.validationErrors.isEmpty)
        XCTAssertEqual(sut.validationErrors.first?.severity, .error)
    }

    // MARK: Helpers

    private func makeSUT() -> ApplyYAMLViewModel {
        ApplyYAMLViewModel(toastEmitter: NoOpToastEmitter())
    }

    private func validYAML() -> String {
        "apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: my-config\n  namespace: default\n"
    }

    private func writeTemp(content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("yaml")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Test doubles

/// Succeeds with HTTP 200 for all apply calls.
private struct SucceedingMutationPort: KubernetesResourceMutationPort {
    func applyYAML(command: ApplyYAML, contextId: UUID) async throws -> Int { 200 }
    func scaleReplicas(command: ScaleReplicas, contextId: UUID) async throws -> Int { 200 }
    func rolloutRestart(command: RolloutRestart, contextId: UUID) async throws -> Int { 200 }
    func deleteResource(command: DeleteResource, contextId: UUID) async throws -> Int { 200 }
    func labelPatch(command: LabelPatch, contextId: UUID) async throws -> Int { 200 }
    func annotationPatch(command: AnnotationPatch, contextId: UUID) async throws -> Int { 200 }
}

/// Records calls to `applyYAML` so tests can inspect the command sent.
private final class SpyMutationPort: KubernetesResourceMutationPort, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastNamespace: String? = nil

    func applyYAML(command: ApplyYAML, contextId: UUID) async throws -> Int {
        callCount += 1
        lastNamespace = command.namespace
        return 200
    }
    func scaleReplicas(command: ScaleReplicas, contextId: UUID) async throws -> Int { 200 }
    func rolloutRestart(command: RolloutRestart, contextId: UUID) async throws -> Int { 200 }
    func deleteResource(command: DeleteResource, contextId: UUID) async throws -> Int { 200 }
    func labelPatch(command: LabelPatch, contextId: UUID) async throws -> Int { 200 }
    func annotationPatch(command: AnnotationPatch, contextId: UUID) async throws -> Int { 200 }
}
