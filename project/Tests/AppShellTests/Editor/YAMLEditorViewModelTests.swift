// Tests/AppShellTests/Editor/YAMLEditorViewModelTests.swift
// Target: AppShellTests
// Coverage: YAMLEditorViewModel lifecycle, validation, dry-run, destructiveness, apply flow

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - Helpers

private func makePodRef() -> AppShell.ResourceRef {
    AppShell.ResourceRef(
        kind: ResourceKind(group: "", version: "v1", kind: "Pod"),
        namespace: "default",
        name: "test-pod"
    )
}

private let validYAML = """
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: default
spec:
  containers:
    - name: app
      image: nginx:latest
"""

private let invalidYAML = """
\tapiVersion: v1
"""

private let yamlWithFinalizer = """
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: default
  finalizers:
    - my-controller/protection
"""

// MARK: - YAMLEditorViewModelTests

@MainActor
final class YAMLEditorViewModelTests: XCTestCase {

    // MARK: - 1. start populates originalText + draftText

    func test_start_populatesOriginalAndDraftText() async {
        let sut = YAMLEditorViewModel()
        let clusterId = ClusterId("test-cluster")
        let ref = makePodRef()

        await sut.start(clusterId: clusterId, ref: ref, initialDraft: validYAML)

        XCTAssertEqual(sut.originalText, validYAML)
        XCTAssertEqual(sut.draftText, validYAML)
        XCTAssertFalse(sut.isDirty)
    }

    // MARK: - 2. validate detects malformed YAML (tab character)

    func test_validate_detectsMalformedYAML() async {
        let sut = YAMLEditorViewModel()
        await sut.start(
            clusterId: ClusterId("c"),
            ref: makePodRef(),
            initialDraft: validYAML
        )
        sut.draftText = invalidYAML

        await sut.validate()

        let errors = sut.validationErrors
        XCTAssertFalse(errors.isEmpty, "Expected at least one error for tab-indented YAML")
        XCTAssertTrue(
            errors.contains { $0.severity == .error },
            "Expected at least one .error severity diagnostic"
        )
    }

    // MARK: - 3. runDryRun returns diff with managed fields

    func test_runDryRun_returnsDiffResult() async {
        let sut = YAMLEditorViewModel()
        await sut.start(
            clusterId: ClusterId("c"),
            ref: makePodRef(),
            initialDraft: validYAML
        )
        sut.draftText = validYAML + "\n  # comment added"

        await sut.runDryRun()

        XCTAssertNotNil(sut.dryRunResult, "Dry-run result should be populated")
        XCTAssertFalse(
            sut.dryRunResult?.diffLines.isEmpty ?? true,
            "Diff lines must not be empty"
        )
    }

    // MARK: - 4. requestApply on dirty → shows confirmation

    func test_requestApply_whenDirty_opensConfirmationSheet() async {
        let sut = YAMLEditorViewModel()
        await sut.start(
            clusterId: ClusterId("c"),
            ref: makePodRef(),
            initialDraft: validYAML
        )
        sut.draftText = validYAML.replacingOccurrences(of: "nginx:latest", with: "nginx:1.25")

        await sut.requestApply()

        XCTAssertTrue(sut.confirmingApply, "Confirmation sheet should be shown when draft is dirty")
    }

    // MARK: - 5. detectDestructiveness for finalizer removal → .destructive

    func test_detectDestructiveness_finalizerRemoved_returnsDestructive() async {
        let sut = YAMLEditorViewModel()
        await sut.start(
            clusterId: ClusterId("c"),
            ref: makePodRef(),
            initialDraft: yamlWithFinalizer
        )
        sut.draftText = validYAML   // finalizer removed in draft

        let level = sut.detectDestructiveness()

        XCTAssertEqual(level, .destructive)
    }

    // MARK: - 6. confirmAndApply on safe → calls mutationPort + audit

    func test_confirmAndApply_safeLevel_recordsAuditEntry() async throws {
        let auditSpy = SpyMutationAuditPort()
        let mutationSpy = SpyMutationPort()

        try await withDependencies {
            $0.mutationAudit = auditSpy
            $0.kubernetesResourceMutation = mutationSpy
        } operation: {
            let sut = YAMLEditorViewModel()
            await sut.start(
                clusterId: ClusterId("c"),
                ref: makePodRef(),
                initialDraft: validYAML
            )
            sut.draftText = validYAML.replacingOccurrences(of: "nginx:latest", with: "nginx:1.25")
            sut.destructivenessLevel = .safe
            sut.confirmingApply = true

            await sut.confirmAndApply()

            let recorded = await auditSpy.recorded
            XCTAssertEqual(recorded.count, 1, "One audit entry must be recorded")
            XCTAssertEqual(recorded.first?.outcome, .succeeded)
        }
    }

    // MARK: - 7. confirmAndApply on destructive without token → blocked

    func test_confirmAndApply_destructive_withoutToken_isBlocked() async throws {
        let auditSpy = SpyMutationAuditPort()
        let mutationSpy = SpyMutationPort()

        try await withDependencies {
            $0.mutationAudit = auditSpy
            $0.kubernetesResourceMutation = mutationSpy
        } operation: {
            let sut = YAMLEditorViewModel()
            await sut.start(
                clusterId: ClusterId("c"),
                ref: makePodRef(),
                initialDraft: yamlWithFinalizer
            )
            sut.draftText = validYAML   // finalizer removed
            sut.destructivenessLevel = .destructive
            sut.confirmationToken = "wrong-name"  // mismatch
            sut.confirmingApply = true

            await sut.confirmAndApply()

            let recorded = await auditSpy.recorded
            XCTAssertTrue(
                recorded.isEmpty,
                "No audit entry should be written when token mismatches"
            )
        }
    }
}

// MARK: - Spies

/// Spy audit port that records calls in-memory.
actor SpyMutationAuditPort: MutationAuditPort {
    private(set) var recorded: [MutationAuditEntry] = []

    func record(_ entry: MutationAuditEntry) async throws {
        recorded.append(entry)
    }

    func complete(
        id: UUID,
        outcome: MutationOutcome,
        completedAt: String,
        kubernetesStatusCode: Int?
    ) async throws {}

    func entries(contextId: UUID, limit: Int, offset: Int) async throws -> [MutationAuditEntry] {
        []
    }
}

/// Spy mutation port that always returns HTTP 200.
struct SpyMutationPort: KubernetesResourceMutationPort {
    func applyYAML(command: ApplyYAML, contextId: UUID) async throws -> Int { 200 }
    func scaleReplicas(command: ScaleReplicas, contextId: UUID) async throws -> Int { 200 }
    func rolloutRestart(command: RolloutRestart, contextId: UUID) async throws -> Int { 200 }
    func deleteResource(command: DeleteResource, contextId: UUID) async throws -> Int { 200 }
    func labelPatch(command: LabelPatch, contextId: UUID) async throws -> Int { 200 }
    func annotationPatch(command: AnnotationPatch, contextId: UUID) async throws -> Int { 200 }
}
