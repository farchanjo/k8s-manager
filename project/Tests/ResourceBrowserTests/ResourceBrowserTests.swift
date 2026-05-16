// ResourceBrowserTests.swift — resource_browser bounded context
// Coverage: domain types, invariants, port sentinels.
// ADR refs: ADR-0012 (mutation policy), ADR-0013 (kind catalogue)

import XCTest
@testable import ResourceBrowser

// MARK: - GroupVersionKind Tests

final class GroupVersionKindTests: XCTestCase {
    func test_core_convenience_setsEmptyGroup() {
        let gvk = GroupVersionKind.core("Pod")
        XCTAssertEqual(gvk.group, "")
        XCTAssertEqual(gvk.version, "v1")
        XCTAssertEqual(gvk.kind, "Pod")
    }

    func test_hashable_equalValues() {
        let a = GroupVersionKind(group: "apps", version: "v1", kind: "Deployment")
        let b = GroupVersionKind(group: "apps", version: "v1", kind: "Deployment")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_hashable_differentKindsAreUnequal() {
        let a = GroupVersionKind(group: "apps", version: "v1", kind: "Deployment")
        let b = GroupVersionKind(group: "apps", version: "v1", kind: "StatefulSet")
        XCTAssertNotEqual(a, b)
    }

    func test_codableRoundTrip() throws {
        let gvk = GroupVersionKind(group: "batch", version: "v1", kind: "Job")
        let data = try JSONEncoder().encode(gvk)
        let decoded = try JSONDecoder().decode(GroupVersionKind.self, from: data)
        XCTAssertEqual(gvk, decoded)
    }
}

// MARK: - KindCatalogue Tests

final class KindCatalogueTests: XCTestCase {
    func test_staticEntries_containsExpectedKinds() {
        let catalogue = KindCatalogue()
        let kindNames = catalogue.all.map(\.gvk.kind)
        XCTAssertTrue(kindNames.contains("Pod"))
        XCTAssertTrue(kindNames.contains("Deployment"))
        XCTAssertTrue(kindNames.contains("ConfigMap"))
        XCTAssertTrue(kindNames.contains("Secret"))
        XCTAssertTrue(kindNames.contains("StatefulSet"))
        XCTAssertTrue(kindNames.contains("DaemonSet"))
        XCTAssertTrue(kindNames.contains("Job"))
        XCTAssertTrue(kindNames.contains("CronJob"))
        XCTAssertTrue(kindNames.contains("Ingress"))
        XCTAssertTrue(kindNames.contains("Role"))
        XCTAssertTrue(kindNames.contains("ClusterRole"))
        XCTAssertTrue(kindNames.contains("CustomResourceDefinition"))
    }

    func test_staticEntries_podIsNamespaced() {
        let catalogue = KindCatalogue()
        let pod = catalogue.descriptor(for: .core("Pod"))
        XCTAssertNotNil(pod)
        XCTAssertTrue(pod?.namespaced == true)
    }

    func test_staticEntries_persistentVolumeIsClusterScoped() {
        let catalogue = KindCatalogue()
        let pv = catalogue.descriptor(for: .core("PersistentVolume"))
        XCTAssertNotNil(pv)
        XCTAssertFalse(pv?.namespaced == true)
    }

    func test_staticEntries_deploymentSupportsScale() {
        let catalogue = KindCatalogue()
        let dep = catalogue.descriptor(
            for: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment")
        )
        XCTAssertNotNil(dep)
        XCTAssertTrue(dep?.supportedSubresources.contains(.scale) == true)
    }

    func test_staticEntries_podSupportsLogs() {
        let catalogue = KindCatalogue()
        let pod = catalogue.descriptor(for: .core("Pod"))
        XCTAssertTrue(pod?.supportedSubresources.contains(.logs) == true)
    }

    func test_register_addsNewEntry() {
        var catalogue = KindCatalogue(entries: [])
        let gvk = GroupVersionKind(group: "example.io", version: "v1", kind: "MyResource")
        let descriptor = ResourceDescriptor(
            gvk: gvk,
            plural: "myresources",
            namespaced: true,
            supportedVerbs: [.list, .get, .watch]
        )
        catalogue.register(descriptor)
        XCTAssertNotNil(catalogue.descriptor(for: gvk))
    }

    func test_remove_deletesEntry() {
        var catalogue = KindCatalogue()
        let gvk = GroupVersionKind.core("Pod")
        XCTAssertNotNil(catalogue.descriptor(for: gvk))
        catalogue.remove(gvk: gvk)
        XCTAssertNil(catalogue.descriptor(for: gvk))
    }

    func test_unknownGVK_returnsNil() {
        let catalogue = KindCatalogue()
        let gvk = GroupVersionKind(group: "unknown.io", version: "v1", kind: "Ghost")
        XCTAssertNil(catalogue.descriptor(for: gvk))
    }
}

// MARK: - MutationCommand Tests

final class MutationCommandTests: XCTestCase {
    func test_applyYAML_targetGVKAndName() {
        let gvk = GroupVersionKind.core("ConfigMap")
        let apply = ApplyYAML(
            targetGVK: gvk,
            namespace: "default",
            name: "my-config",
            manifestYAML: "apiVersion: v1\nkind: ConfigMap",
            manifestDigest: String(repeating: "a", count: 64)
        )
        let cmd = MutationCommand.applyYAML(apply)
        XCTAssertEqual(cmd.targetGVK, gvk)
        XCTAssertEqual(cmd.name, "my-config")
    }

    func test_applyYAML_defaultFieldManager() {
        let apply = ApplyYAML(
            targetGVK: .core("ConfigMap"),
            namespace: "default",
            name: "cm",
            manifestYAML: "a: b",
            manifestDigest: String(repeating: "0", count: 64)
        )
        XCTAssertEqual(apply.fieldManager, FieldManager.k8sManager)
    }

    func test_applyYAML_forceConflictsDefaultsFalse() {
        let apply = ApplyYAML(
            targetGVK: .core("ConfigMap"),
            namespace: nil,
            name: "x",
            manifestYAML: "a: b",
            manifestDigest: String(repeating: "0", count: 64)
        )
        XCTAssertFalse(apply.forceConflicts)
    }

    func test_scaleReplicas_desiredReplicasZeroAllowed() {
        let cmd = ScaleReplicas(
            targetGVK: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
            namespace: "default",
            name: "web",
            desiredReplicas: 0
        )
        XCTAssertEqual(cmd.desiredReplicas, 0)
    }

    func test_deleteResource_defaultPropagationBackground() {
        let del = DeleteResource(
            targetGVK: .core("Pod"),
            namespace: "default",
            name: "my-pod"
        )
        XCTAssertEqual(del.propagationPolicy, .background)
    }

    func test_labelPatch_targetName() {
        let patch = LabelPatch(
            targetGVK: .core("Service"),
            namespace: "default",
            name: "svc",
            labelsToSet: ["env": "prod"],
            labelsToRemove: ["old-label"]
        )
        let cmd = MutationCommand.labelPatch(patch)
        XCTAssertEqual(cmd.name, "svc")
    }

    func test_annotationPatch_codableRoundTrip() throws {
        let patch = AnnotationPatch(
            targetGVK: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
            namespace: "default",
            name: "dep",
            annotationsToSet: ["key": "value"],
            annotationsToRemove: []
        )
        let cmd = MutationCommand.annotationPatch(patch)
        let data = try JSONEncoder().encode(cmd)
        let decoded = try JSONDecoder().decode(MutationCommand.self, from: data)
        XCTAssertEqual(cmd, decoded)
    }
}

// MARK: - MutationAuditEntry Tests

final class MutationAuditEntryTests: XCTestCase {
    func test_genesisDigest_is64ZeroHexCharacters() {
        XCTAssertEqual(MutationAuditEntry.genesisDigest.count, 64)
        XCTAssertTrue(MutationAuditEntry.genesisDigest.allSatisfy { $0 == "0" })
    }

    func test_init_setsAllFields() {
        let id = UUID()
        let contextId = UUID()
        let tokenId = UUID()
        let cmd = MutationCommand.scaleReplicas(
            ScaleReplicas(
                targetGVK: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
                namespace: "default",
                name: "web",
                desiredReplicas: 3
            )
        )
        let entry = MutationAuditEntry(
            id: id,
            requestedAt: "2026-05-15T21:00:00Z",
            kubernetesContextId: contextId,
            command: cmd,
            outcome: .succeeded,
            kubernetesStatusCode: 200,
            confirmationToken: tokenId,
            previousEntryDigest: MutationAuditEntry.genesisDigest
        )
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.outcome, .succeeded)
        XCTAssertEqual(entry.kubernetesStatusCode, 200)
        XCTAssertNil(entry.completedAt)
        XCTAssertEqual(entry.keyVersion, "v1")
    }

    func test_codableRoundTrip() throws {
        let cmd = MutationCommand.rolloutRestart(
            RolloutRestart(
                targetGVK: GroupVersionKind(group: "apps", version: "v1", kind: "DaemonSet"),
                namespace: "kube-system",
                name: "fluentd",
                restartedAt: "2026-05-15T21:00:00Z"
            )
        )
        let entry = MutationAuditEntry(
            id: UUID(),
            requestedAt: "2026-05-15T21:00:00Z",
            kubernetesContextId: UUID(),
            command: cmd,
            outcome: .cancelled,
            confirmationToken: UUID(),
            previousEntryDigest: MutationAuditEntry.genesisDigest
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(MutationAuditEntry.self, from: data)
        XCTAssertEqual(entry.id, decoded.id)
        XCTAssertEqual(entry.outcome, decoded.outcome)
    }
}

// MARK: - EditorSession Tests

final class EditorSessionTests: XCTestCase {
    func test_isDirty_falseWhenContentsMatch() {
        let session = EditorSession(
            kubernetesContextId: UUID(),
            sourceFormat: .yaml,
            currentContent: "a: b",
            originalContent: "a: b",
            openedAt: "2026-05-15T21:00:00Z",
            lastModifiedAt: "2026-05-15T21:00:00Z"
        )
        XCTAssertFalse(session.isDirty)
    }

    func test_isDirty_trueWhenContentsDiffer() {
        var session = EditorSession(
            kubernetesContextId: UUID(),
            sourceFormat: .yaml,
            currentContent: "a: b",
            originalContent: "a: b",
            openedAt: "2026-05-15T21:00:00Z",
            lastModifiedAt: "2026-05-15T21:00:00Z"
        )
        session.currentContent = "a: c"
        XCTAssertTrue(session.isDirty)
    }

    func test_debounceMs_clampedToMinimum() {
        let session = EditorSession(
            kubernetesContextId: UUID(),
            sourceFormat: .json,
            currentContent: "{}",
            originalContent: "{}",
            openedAt: "2026-05-15T21:00:00Z",
            lastModifiedAt: "2026-05-15T21:00:00Z",
            debounceMs: 10 // below minimum of 50
        )
        XCTAssertEqual(session.debounceMs, 50)
    }

    func test_debounceMs_clampedToMaximum() {
        let session = EditorSession(
            kubernetesContextId: UUID(),
            sourceFormat: .yaml,
            currentContent: "a: b",
            originalContent: "a: b",
            openedAt: "2026-05-15T21:00:00Z",
            lastModifiedAt: "2026-05-15T21:00:00Z",
            debounceMs: 99999 // above maximum of 5000
        )
        XCTAssertEqual(session.debounceMs, 5000)
    }

    func test_editorState_dryRunCompleteCarriesPreview() {
        let conflicts = [FieldConflict(fieldPath: "/spec/replicas", currentManager: "kubectl")]
        let state = EditorState.dryRunComplete(diffPreview: "- foo\n+ bar\n", conflicts: conflicts)
        if case .dryRunComplete(let preview, let gotConflicts) = state {
            XCTAssertTrue(preview.contains("foo"))
            XCTAssertEqual(gotConflicts.count, 1)
        } else {
            XCTFail("Unexpected state")
        }
    }

    func test_editorState_appliedCarriesOutcome() {
        let state = EditorState.applied(outcome: .succeeded, outcomeDetail: "Applied successfully.")
        if case .applied(let outcome, _) = state {
            XCTAssertEqual(outcome, .succeeded)
        } else {
            XCTFail("Unexpected state")
        }
    }
}

// MARK: - Draft Tests

final class DraftTests: XCTestCase {
    func test_init_defaultsAutoSavedTrue() {
        let draft = Draft(
            editorSessionId: UUID(),
            sourceFormat: .yaml,
            content: "a: b",
            savedAt: "2026-05-15T21:00:00Z"
        )
        XCTAssertTrue(draft.autoSaved)
    }

    func test_init_defaultsSensitiveContentRedactedFalse() {
        let draft = Draft(
            editorSessionId: UUID(),
            sourceFormat: .yaml,
            content: "a: b",
            savedAt: "2026-05-15T21:00:00Z"
        )
        XCTAssertFalse(draft.sensitiveContentRedacted)
    }

    func test_init_redactedFlagCanBeSetTrue() {
        let draft = Draft(
            editorSessionId: UUID(),
            sourceFormat: .yaml,
            content: "data:\n  key: [REDACTED]",
            sensitiveContentRedacted: true,
            savedAt: "2026-05-15T21:00:00Z"
        )
        XCTAssertTrue(draft.sensitiveContentRedacted)
    }

    func test_codableRoundTrip() throws {
        let original = Draft(
            id: UUID(),
            editorSessionId: UUID(),
            resourceRef: ResourceRef(apiVersion: "v1", kind: "Secret", namespace: "default", name: "my-secret"),
            sourceFormat: .yaml,
            content: "data:\n  key: [REDACTED]",
            sensitiveContentRedacted: true,
            savedAt: "2026-05-15T21:05:00Z",
            autoSaved: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Draft.self, from: data)
        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.sensitiveContentRedacted, decoded.sensitiveContentRedacted)
        XCTAssertEqual(original.resourceRef?.kind, decoded.resourceRef?.kind)
    }
}

// MARK: - Port sentinel Tests

final class PortSentinelTests: XCTestCase {
    func test_unimplementedListPort_throws() async {
        let port = UnimplementedKubernetesResourceListPort()
        do {
            _ = try await port.list(
                gvk: .core("Pod"),
                namespace: "default",
                contextId: UUID()
            )
            XCTFail("Expected unimplemented error")
        } catch ResourceListError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_unimplementedMutationPort_throws() async {
        let port = UnimplementedKubernetesResourceMutationPort()
        let apply = ApplyYAML(
            targetGVK: .core("ConfigMap"),
            namespace: "default",
            name: "x",
            manifestYAML: "a: b",
            manifestDigest: String(repeating: "0", count: 64)
        )
        do {
            _ = try await port.applyYAML(command: apply, contextId: UUID())
            XCTFail("Expected unimplemented error")
        } catch MutationError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_unimplementedAuditPort_throws() async {
        let port = UnimplementedMutationAuditPort()
        let cmd = MutationCommand.scaleReplicas(
            ScaleReplicas(
                targetGVK: GroupVersionKind(group: "apps", version: "v1", kind: "Deployment"),
                namespace: "default",
                name: "web",
                desiredReplicas: 2
            )
        )
        let entry = MutationAuditEntry(
            id: UUID(),
            requestedAt: "2026-05-15T21:00:00Z",
            kubernetesContextId: UUID(),
            command: cmd,
            outcome: .succeeded,
            confirmationToken: UUID(),
            previousEntryDigest: MutationAuditEntry.genesisDigest
        )
        do {
            try await port.record(entry)
            XCTFail("Expected unimplemented error")
        } catch AuditError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_unimplementedDraftStoragePort_throws() async {
        let port = UnimplementedDraftStoragePort()
        let draft = Draft(
            editorSessionId: UUID(),
            sourceFormat: .yaml,
            content: "a: b",
            savedAt: "2026-05-15T21:00:00Z"
        )
        do {
            try await port.save(draft)
            XCTFail("Expected unimplemented error")
        } catch DraftStorageError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_unimplementedWatchPort_streamThrows() async {
        let port = UnimplementedResourceWatchPort()
        let stream = port.watchResources(
            gvk: .core("Pod"),
            namespace: "default",
            contextId: UUID(),
            resourceVersion: nil
        )
        do {
            for try await _ in stream {
                XCTFail("Expected no elements")
            }
            XCTFail("Expected stream to throw")
        } catch ResourceWatchError.unimplemented {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - ResourceView Tests

final class ResourceViewTests: XCTestCase {
    func test_resourceListItem_init() {
        let id = UUID()
        let gvk = GroupVersionKind.core("Pod")
        let item = ResourceListItem(
            id: id,
            gvk: gvk,
            namespace: "default",
            name: "my-pod",
            uid: "abc-123",
            creationTimestamp: "2026-05-15T20:00:00Z",
            status: "Running",
            ageSeconds: 3600
        )
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.name, "my-pod")
        XCTAssertEqual(item.status, "Running")
        XCTAssertEqual(item.ageSeconds, 3600)
        XCTAssertTrue(item.labels.isEmpty)
    }

    func test_resourceDetail_emptyConditionsAndEvents() {
        let item = ResourceListItem(
            id: UUID(),
            gvk: .core("Pod"),
            namespace: "default",
            name: "p",
            uid: "u",
            creationTimestamp: "2026-05-15T20:00:00Z",
            status: "",
            ageSeconds: 0
        )
        let detail = ResourceDetail(listItem: item, rawJSON: "{}")
        XCTAssertTrue(detail.conditions.isEmpty)
        XCTAssertTrue(detail.recentEvents.isEmpty)
    }

    func test_statusCondition_codableRoundTrip() throws {
        let condition = StatusCondition(
            conditionType: "Ready",
            status: .true,
            reason: "PodRunning",
            message: "All containers running.",
            lastTransitionTime: "2026-05-15T20:00:00Z"
        )
        let data = try JSONEncoder().encode(condition)
        let decoded = try JSONDecoder().decode(StatusCondition.self, from: data)
        XCTAssertEqual(condition, decoded)
    }

    func test_eventSummary_warningType() {
        let event = EventSummary(
            reason: "BackOff",
            message: "Back-off restarting failed container",
            eventType: .warning,
            count: 5,
            lastTimestamp: "2026-05-15T21:00:00Z"
        )
        XCTAssertEqual(event.eventType, .warning)
        XCTAssertEqual(event.count, 5)
    }
}

// MARK: - ResourceBrowserService Config Tests

final class ResourceBrowserServiceConfigTests: XCTestCase {
    func test_defaultFieldManager() {
        let config = ResourceBrowserServiceConfig(kubernetesContextId: UUID())
        XCTAssertEqual(config.activeFieldManager, FieldManager.k8sManager)
    }

    func test_dispatchConfig_maxTokenAge_default() {
        let config = MutationDispatchServiceConfig(kubernetesContextId: UUID())
        XCTAssertEqual(config.maxConfirmationTokenAgeSeconds, 300)
    }

    func test_factoryConfig_sensitiveAnnotationKeysContainsToken() {
        let config = MutationCommandFactoryConfig(kubernetesContextId: UUID())
        XCTAssertTrue(config.sensitiveAnnotationKeys.contains("token"))
        XCTAssertTrue(config.sensitiveAnnotationKeys.contains("password"))
        XCTAssertTrue(
            config.sensitiveAnnotationKeys.contains(
                "kubectl.kubernetes.io/last-applied-configuration"
            )
        )
    }

    func test_fieldManager_canonicalValue() {
        XCTAssertEqual(FieldManager.k8sManager, "com.archanjo.K8sManager")
    }
}
