// Tests/AppShellTests/RowActionMenuTests.swift
// Coverage: RowActionMenuBuilder canonical item list per kind per ADR-0061.
//
// ADR-0061 contract:
// - Base set (all families): editYAML, viewEvents, copyResourceLink, saveYAML, delete.
// - Workloads extension: scale (Deployment/StatefulSet/ReplicaSet), rolloutRestart
//   (Deployment/StatefulSet/DaemonSet), viewLogs+openTerminal+portForward (Pod).
// - Network extension: portForward (Service).
// - AccessControl extension: viewSubjects (RoleBinding/ClusterRoleBinding).
// - Config extension: revealData (Secret).
// - Storage / Cluster / CustomResources: base set only.

import XCTest
@testable import AppShell

// MARK: - Base set assertions

final class RowActionMenuBuilderBaseSetTests: XCTestCase {

    private func baseIds(for context: RowActionContext) -> [String] {
        RowActionMenuBuilder.actions(for: context).map(\.id)
    }

    func test_baseSet_editYAMLPresentForAllFamilies() {
        let families: [(KindFamily, String)] = [
            (.workloads, "Job"),
            (.config, "ConfigMap"),
            (.network, "Ingress"),
            (.storage, "PersistentVolume"),
            (.accessControl, "Role"),
            (.cluster, "Namespace"),
            (.customResources, "Foo"),
        ]
        for (family, kind) in families {
            let context = RowActionContext(kind: kind, name: "test", family: family)
            XCTAssertTrue(baseIds(for: context).contains("edit-yaml"),
                          "editYAML missing for kind=\(kind)")
        }
    }

    func test_baseSet_deleteLastItem() {
        let context = RowActionContext(kind: "ConfigMap", name: "cm", family: .config)
        let ids = baseIds(for: context)
        XCTAssertEqual(ids.last, "delete", "delete must be last base-set item")
    }

    func test_baseSet_deleteRequiresDoubleConfirm() {
        let context = RowActionContext(kind: "ConfigMap", name: "cm", family: .config)
        let deleteAction = RowActionMenuBuilder.actions(for: context)
            .first { $0.id == "delete" }
        XCTAssertEqual(deleteAction?.requiresDoubleConfirm, true)
    }

    func test_baseSet_editYAMLIsMutating() {
        let context = RowActionContext(kind: "ConfigMap", name: "cm", family: .config)
        let action = RowActionMenuBuilder.actions(for: context).first { $0.id == "edit-yaml" }
        XCTAssertEqual(action?.isMutating, true)
    }

    func test_baseSet_saveYAMLIsNotMutating() {
        let context = RowActionContext(kind: "ConfigMap", name: "cm", family: .config)
        let action = RowActionMenuBuilder.actions(for: context).first { $0.id == "save-yaml" }
        XCTAssertEqual(action?.isMutating, false)
    }

    func test_baseSet_viewEventsIsNotMutating() {
        let context = RowActionContext(kind: "ConfigMap", name: "cm", family: .config)
        let action = RowActionMenuBuilder.actions(for: context).first { $0.id == "view-events" }
        XCTAssertEqual(action?.isMutating, false)
    }
}

// MARK: - Workloads family

final class RowActionMenuBuilderWorkloadsTests: XCTestCase {

    private func ids(kind: String) -> [String] {
        let ctx = RowActionContext(kind: kind, name: "r", family: .workloads)
        return RowActionMenuBuilder.actions(for: ctx).map(\.id)
    }

    func test_deployment_hasScaleAndRolloutRestart() {
        let ids = ids(kind: "Deployment")
        XCTAssertTrue(ids.contains("scale"))
        XCTAssertTrue(ids.contains("rollout-restart"))
    }

    func test_statefulSet_hasScaleAndRolloutRestart() {
        let ids = ids(kind: "StatefulSet")
        XCTAssertTrue(ids.contains("scale"))
        XCTAssertTrue(ids.contains("rollout-restart"))
    }

    func test_daemonSet_hasRolloutRestartButNotScale() {
        let ids = ids(kind: "DaemonSet")
        XCTAssertFalse(ids.contains("scale"), "DaemonSet must not have scale")
        XCTAssertTrue(ids.contains("rollout-restart"))
    }

    func test_replicaSet_hasScaleButNotRolloutRestart() {
        let ids = ids(kind: "ReplicaSet")
        XCTAssertTrue(ids.contains("scale"))
        XCTAssertFalse(ids.contains("rollout-restart"), "ReplicaSet must not have rollout-restart")
    }

    func test_pod_hasViewLogsOpenTerminalPortForward() {
        let ids = ids(kind: "Pod")
        XCTAssertTrue(ids.contains("view-logs"))
        XCTAssertTrue(ids.contains("open-terminal"))
        XCTAssertTrue(ids.contains("port-forward"))
    }

    func test_pod_doesNotHaveScaleOrRolloutRestart() {
        let ids = ids(kind: "Pod")
        XCTAssertFalse(ids.contains("scale"))
        XCTAssertFalse(ids.contains("rollout-restart"))
    }

    func test_job_hasBaseSetOnly() {
        let ids = ids(kind: "Job")
        let extraIds: [String] = ["scale", "rollout-restart", "view-logs", "open-terminal",
                                  "port-forward", "view-subjects", "reveal-data"]
        for extra in extraIds {
            XCTAssertFalse(ids.contains(extra), "Job must not have \(extra)")
        }
    }

    func test_cronJob_hasBaseSetOnly() {
        let ids = ids(kind: "CronJob")
        XCTAssertFalse(ids.contains("scale"))
        XCTAssertFalse(ids.contains("rollout-restart"))
    }

    func test_hpa_hasBaseSetOnly() {
        let ids = ids(kind: "HorizontalPodAutoscaler")
        XCTAssertFalse(ids.contains("scale"))
    }

    func test_replicationController_hasBaseSetOnly() {
        let ids = ids(kind: "ReplicationController")
        XCTAssertFalse(ids.contains("view-logs"))
    }
}

// MARK: - Network family

final class RowActionMenuBuilderNetworkTests: XCTestCase {

    private func ids(kind: String) -> [String] {
        let ctx = RowActionContext(kind: kind, name: "r", family: .network)
        return RowActionMenuBuilder.actions(for: ctx).map(\.id)
    }

    func test_service_hasPortForward() {
        XCTAssertTrue(ids(kind: "Service").contains("port-forward"))
    }

    func test_ingress_doesNotHavePortForward() {
        XCTAssertFalse(ids(kind: "Ingress").contains("port-forward"))
    }

    func test_networkPolicy_hasBaseSetOnly() {
        let ids = ids(kind: "NetworkPolicy")
        XCTAssertFalse(ids.contains("port-forward"))
        XCTAssertFalse(ids.contains("scale"))
    }
}

// MARK: - AccessControl family

final class RowActionMenuBuilderAccessControlTests: XCTestCase {

    private func ids(kind: String) -> [String] {
        let ctx = RowActionContext(kind: kind, name: "r", family: .accessControl)
        return RowActionMenuBuilder.actions(for: ctx).map(\.id)
    }

    func test_roleBinding_hasViewSubjects() {
        XCTAssertTrue(ids(kind: "RoleBinding").contains("view-subjects"))
    }

    func test_clusterRoleBinding_hasViewSubjects() {
        XCTAssertTrue(ids(kind: "ClusterRoleBinding").contains("view-subjects"))
    }

    func test_role_doesNotHaveViewSubjects() {
        XCTAssertFalse(ids(kind: "Role").contains("view-subjects"))
    }

    func test_clusterRole_doesNotHaveViewSubjects() {
        XCTAssertFalse(ids(kind: "ClusterRole").contains("view-subjects"))
    }
}

// MARK: - Config family

final class RowActionMenuBuilderConfigTests: XCTestCase {

    private func ids(kind: String) -> [String] {
        let ctx = RowActionContext(kind: kind, name: "r", family: .config)
        return RowActionMenuBuilder.actions(for: ctx).map(\.id)
    }

    func test_secret_hasRevealData() {
        XCTAssertTrue(ids(kind: "Secret").contains("reveal-data"))
    }

    func test_configMap_doesNotHaveRevealData() {
        XCTAssertFalse(ids(kind: "ConfigMap").contains("reveal-data"))
    }

    func test_resourceQuota_hasBaseSetOnly() {
        let ids = ids(kind: "ResourceQuota")
        XCTAssertFalse(ids.contains("reveal-data"))
        XCTAssertFalse(ids.contains("scale"))
    }
}

// MARK: - Storage family

final class RowActionMenuBuilderStorageTests: XCTestCase {

    func test_pvc_hasBaseSetOnly() {
        let ctx = RowActionContext(kind: "PersistentVolumeClaim", name: "pvc", family: .storage)
        let ids = RowActionMenuBuilder.actions(for: ctx).map(\.id)
        XCTAssertFalse(ids.contains("scale"))
        XCTAssertFalse(ids.contains("view-subjects"))
        XCTAssertFalse(ids.contains("port-forward"))
    }
}

// MARK: - Accelerator uniqueness

final class RowActionMenuBuilderAcceleratorTests: XCTestCase {

    func test_workloadsPod_allAcceleratorsUnique() {
        let ctx = RowActionContext(kind: "Pod", name: "p", family: .workloads)
        let actions = RowActionMenuBuilder.actions(for: ctx)
        let keys = actions.map(\.acceleratorKey)
        let unique = Set(keys)
        XCTAssertEqual(keys.count, unique.count, "Duplicate accelerator keys in Pod menu")
    }

    func test_service_allAcceleratorsUnique() {
        let ctx = RowActionContext(kind: "Service", name: "s", family: .network)
        let actions = RowActionMenuBuilder.actions(for: ctx)
        let keys = actions.map(\.acceleratorKey)
        XCTAssertEqual(keys.count, Set(keys).count, "Duplicate accelerator keys in Service menu")
    }

    func test_roleBinding_allAcceleratorsUnique() {
        let ctx = RowActionContext(kind: "RoleBinding", name: "rb", family: .accessControl)
        let actions = RowActionMenuBuilder.actions(for: ctx)
        let keys = actions.map(\.acceleratorKey)
        XCTAssertEqual(keys.count, Set(keys).count, "Duplicate accelerator keys in RoleBinding menu")
    }
}
