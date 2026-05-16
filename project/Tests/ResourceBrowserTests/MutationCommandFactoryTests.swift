// MutationCommandFactoryTests.swift — ResourceBrowserTests target
// Coverage: MutationCommandFactory — intent translation, digest, redaction.
// ADR refs: ADR-0012 (mutation policy, sensitive-key redaction)

import XCTest
@testable import ResourceBrowser
import SharedKernel

// MARK: - Helpers

private func makeDescriptor(
    gvk: GroupVersionKind = GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
    verbs: [SupportedVerb] = [.list, .get, .watch, .patch, .delete]
) -> ResourceDescriptor {
    ResourceDescriptor(
        gvk: gvk,
        plural: gvk.kind.lowercased() + "s",
        namespaced: true,
        supportedVerbs: verbs
    )
}

private func makeFactory(contextId: UUID = UUID()) -> MutationCommandFactory {
    MutationCommandFactory(config: MutationCommandFactoryConfig(kubernetesContextId: contextId))
}

// MARK: - Tests

final class MutationCommandFactoryApplyTests: XCTestCase {

    func test_build_applyYAML_returnsApplyYAMLCommand() throws {
        let factory = makeFactory()
        let descriptor = makeDescriptor()
        let intent = MutationIntent.applyYAML(
            manifestYAML: "apiVersion: apps/v1\nkind: Deployment",
            targetGVK: descriptor.gvk,
            namespace: "default",
            name: "my-deploy",
            forceConflicts: false
        )
        let command = try factory.build(intent: intent, target: descriptor, confirmationToken: UUID())
        guard case .applyYAML(let apply) = command else {
            return XCTFail("Expected .applyYAML")
        }
        XCTAssertEqual(apply.name, "my-deploy")
        XCTAssertEqual(apply.fieldManager, FieldManager.k8sManager)
        XCTAssertFalse(apply.forceConflicts)
        XCTAssertEqual(apply.manifestDigest.count, 64, "SHA-256 hex digest should be 64 chars")
    }

    func test_build_applyYAML_digestIsDeterministic() throws {
        let factory = makeFactory()
        let descriptor = makeDescriptor()
        let yaml = "apiVersion: v1\nkind: ConfigMap"
        let intent = MutationIntent.applyYAML(
            manifestYAML: yaml,
            targetGVK: .core("ConfigMap"),
            namespace: "default",
            name: "cfg",
            forceConflicts: false
        )
        let c1 = try factory.build(intent: intent, target: descriptor, confirmationToken: UUID())
        let c2 = try factory.build(intent: intent, target: descriptor, confirmationToken: UUID())
        if case .applyYAML(let a1) = c1, case .applyYAML(let a2) = c2 {
            XCTAssertEqual(a1.manifestDigest, a2.manifestDigest)
        } else {
            XCTFail("Both should be .applyYAML")
        }
    }

    func test_build_applyYAML_redactsSensitiveAnnotations() throws {
        let factory = makeFactory()
        let descriptor = makeDescriptor(gvk: .core("ConfigMap"), verbs: [.patch])
        let yaml = "metadata:\n  annotations:\n    token: super-secret"
        let intent = MutationIntent.applyYAML(
            manifestYAML: yaml,
            targetGVK: .core("ConfigMap"),
            namespace: "default",
            name: "cfg",
            forceConflicts: false
        )
        let command = try factory.build(intent: intent, target: descriptor, confirmationToken: UUID())
        guard case .applyYAML(let apply) = command else { return XCTFail() }
        XCTAssertTrue(apply.manifestYAML.contains("<redacted>"), "Sensitive value must be redacted")
        XCTAssertFalse(apply.manifestYAML.contains("super-secret"))
    }
}

final class MutationCommandFactoryScaleTests: XCTestCase {

    func test_build_scaleReplicas_producesCorrectCommand() throws {
        let factory = makeFactory()
        let descriptor = makeDescriptor()
        let intent = MutationIntent.scaleReplicas(
            targetGVK: descriptor.gvk,
            namespace: "prod",
            name: "api",
            desiredReplicas: 5
        )
        let command = try factory.build(intent: intent, target: descriptor, confirmationToken: UUID())
        guard case .scaleReplicas(let scale) = command else { return XCTFail() }
        XCTAssertEqual(scale.desiredReplicas, 5)
        XCTAssertEqual(scale.namespace, "prod")
    }

    func test_build_deleteResource_propagationPolicyPreserved() throws {
        let factory = makeFactory()
        let descriptor = makeDescriptor(gvk: .core("Pod"))
        let intent = MutationIntent.deleteResource(
            targetGVK: .core("Pod"),
            namespace: "default",
            name: "stale-pod",
            gracePeriodSeconds: 0,
            propagationPolicy: .foreground
        )
        let command = try factory.build(intent: intent, target: descriptor, confirmationToken: UUID())
        guard case .deleteResource(let del) = command else { return XCTFail() }
        XCTAssertEqual(del.propagationPolicy, .foreground)
        XCTAssertEqual(del.gracePeriodSeconds, 0)
    }
}

final class MutationCommandFactoryAllowlistTests: XCTestCase {

    func test_build_gvkWithoutPatchOrDelete_throwsGvkNotInAllowlist() {
        let factory = makeFactory()
        let descriptor = makeDescriptor(verbs: [.list, .get]) // no patch or delete
        let intent = MutationIntent.scaleReplicas(
            targetGVK: descriptor.gvk,
            namespace: "ns",
            name: "dep",
            desiredReplicas: 1
        )
        XCTAssertThrowsError(
            try factory.build(intent: intent, target: descriptor, confirmationToken: UUID())
        ) { error in
            guard case MutationCommandFactoryError.gvkNotInAllowlist = error else {
                XCTFail("Expected gvkNotInAllowlist, got \(error)")
                return
            }
        }
    }

    func test_build_rolloutRestart_injectsISO8601Timestamp() throws {
        let factory = makeFactory()
        let descriptor = makeDescriptor()
        let intent = MutationIntent.rolloutRestart(
            targetGVK: descriptor.gvk,
            namespace: "default",
            name: "dep"
        )
        let command = try factory.build(intent: intent, target: descriptor, confirmationToken: UUID())
        guard case .rolloutRestart(let restart) = command else { return XCTFail() }
        XCTAssertFalse(restart.restartedAt.isEmpty)
        XCTAssertTrue(restart.restartedAt.contains("T"), "restartedAt should be ISO8601")
    }
}
