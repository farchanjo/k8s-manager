// Tests/AppShellTests/ResourceListFABTests.swift
// Coverage: FABVisibilityPolicy per ADR-0066.
//
// ADR-0066 contract:
// - FAB visible for kinds with `create` in the operation matrix.
// - FAB hidden (not disabled) for Node, Event, CSINode, CSIDriver.
// - FABCreatePath enum carries three distinct paths.

import XCTest
@testable import AppShell

// MARK: - FABVisibilityPolicyTests

final class FABVisibilityPolicyTests: XCTestCase {

    // MARK: Excluded kinds (FAB hidden)

    func test_node_isFABHidden() {
        XCTAssertFalse(FABVisibilityPolicy.isVisible(for: "Node"))
    }

    func test_event_isFABHidden() {
        XCTAssertFalse(FABVisibilityPolicy.isVisible(for: "Event"))
    }

    func test_csiNode_isFABHidden() {
        XCTAssertFalse(FABVisibilityPolicy.isVisible(for: "CSINode"))
    }

    func test_csiDriver_isFABHidden() {
        XCTAssertFalse(FABVisibilityPolicy.isVisible(for: "CSIDriver"))
    }

    // MARK: Included kinds (FAB visible)

    func test_deployment_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "Deployment"))
    }

    func test_pod_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "Pod"))
    }

    func test_statefulSet_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "StatefulSet"))
    }

    func test_daemonSet_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "DaemonSet"))
    }

    func test_configMap_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "ConfigMap"))
    }

    func test_secret_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "Secret"))
    }

    func test_service_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "Service"))
    }

    func test_ingress_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "Ingress"))
    }

    func test_persistentVolumeClaim_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "PersistentVolumeClaim"))
    }

    func test_namespace_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "Namespace"))
    }

    func test_role_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "Role"))
    }

    func test_clusterRole_isFABVisible() {
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "ClusterRole"))
    }

    func test_unknownKind_isFABVisibleByDefault() {
        // Kinds not in the excluded set receive FAB by default
        XCTAssertTrue(FABVisibilityPolicy.isVisible(for: "MyCustomResource"))
    }
}

// MARK: - FABCreatePathTests

final class FABCreatePathTests: XCTestCase {

    func test_paths_areDistinct() {
        let paths: [FABCreatePath] = [.createFromScratch, .pasteFromClipboard, .forkFromSelected]
        let uniquePaths = Set(paths)
        XCTAssertEqual(paths.count, uniquePaths.count, "All FABCreatePath cases must be distinct")
    }

    func test_createFromScratch_isHashable() {
        let path = FABCreatePath.createFromScratch
        XCTAssertEqual(path, FABCreatePath.createFromScratch)
    }

    func test_pasteFromClipboard_isHashable() {
        let path = FABCreatePath.pasteFromClipboard
        XCTAssertEqual(path, FABCreatePath.pasteFromClipboard)
    }

    func test_forkFromSelected_isHashable() {
        let path = FABCreatePath.forkFromSelected
        XCTAssertEqual(path, FABCreatePath.forkFromSelected)
    }

    func test_forkFromSelected_isDistinctFromCreateFromScratch() {
        XCTAssertNotEqual(FABCreatePath.forkFromSelected, FABCreatePath.createFromScratch)
    }
}
