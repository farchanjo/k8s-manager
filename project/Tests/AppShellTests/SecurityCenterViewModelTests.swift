// Tests/AppShellTests/SecurityCenterViewModelTests.swift
// Coverage: ADR-0068 — Security Center sidebar taxonomy, DocumentTab routing,
// SecurityCenterEntry domain model, and SidebarNode expansion.
// ADR ref: ADR-0068 (Security Center sidebar surface and content)

import XCTest
@testable import AppShell
import SharedKernel

// MARK: - SecurityCenterTaxonomyTests

final class SecurityCenterTaxonomyTests: XCTestCase {

    // MARK: SidebarNode children

    func test_securityCenterNode_hasExactlyFourChildren() {
        let children = SidebarNode.securityCenter.children
        XCTAssertNotNil(children, "securityCenter must be an expandable group node")
        XCTAssertEqual(children?.count, 4, "exactly 4 sub-entries per ADR-0068")
    }

    func test_securityCenterChildren_areInFixedOrder() {
        let children = SidebarNode.securityCenter.children ?? []
        XCTAssertEqual(children[0], .securityOverviewEntry)
        XCTAssertEqual(children[1], .securityImagesEntry)
        XCTAssertEqual(children[2], .securityResourcesEntry)
        XCTAssertEqual(children[3], .securityRolesEntry)
    }

    func test_securityCenterNode_isExpandable() {
        XCTAssertTrue(SidebarNode.securityCenter.isExpandable)
    }

    func test_securityCenterNode_hasNoDirectTab() {
        let tab = SidebarNode.securityCenter.toDocumentTab(clusterId: testClusterId)
        XCTAssertNil(tab, "securityCenter group header must not produce a tab directly")
    }

    // MARK: SidebarNode leaf tab mapping

    func test_overviewEntry_mapsToSecurityOverviewTab() {
        let tab = SidebarNode.securityOverviewEntry.toDocumentTab(clusterId: testClusterId)
        if case .securityOverview(let cid) = tab {
            XCTAssertEqual(cid, testClusterId)
        } else {
            XCTFail("Expected .securityOverview tab, got \(String(describing: tab))")
        }
    }

    func test_imagesEntry_mapsToSecurityImagesTab() {
        let tab = SidebarNode.securityImagesEntry.toDocumentTab(clusterId: testClusterId)
        if case .securityImages(let cid) = tab {
            XCTAssertEqual(cid, testClusterId)
        } else {
            XCTFail("Expected .securityImages tab, got \(String(describing: tab))")
        }
    }

    func test_resourcesEntry_mapsToSecurityResourcesTab() {
        let tab = SidebarNode.securityResourcesEntry.toDocumentTab(clusterId: testClusterId)
        if case .securityResources(let cid) = tab {
            XCTAssertEqual(cid, testClusterId)
        } else {
            XCTFail("Expected .securityResources tab, got \(String(describing: tab))")
        }
    }

    func test_rolesEntry_mapsToSecurityRolesTab() {
        let tab = SidebarNode.securityRolesEntry.toDocumentTab(clusterId: testClusterId)
        if case .securityRoles(let cid) = tab {
            XCTAssertEqual(cid, testClusterId)
        } else {
            XCTFail("Expected .securityRoles tab, got \(String(describing: tab))")
        }
    }

    // MARK: SecurityCenterEntry domain model

    func test_allEntries_haveDistinctSidebarNodes() {
        let nodes = SecurityCenterEntry.allCases.map(\.sidebarNode)
        let unique = Set(nodes)
        XCTAssertEqual(unique.count, SecurityCenterEntry.allCases.count,
                       "each SecurityCenterEntry must map to a distinct SidebarNode")
    }

    func test_allEntries_haveNonEmptyTitles() {
        for entry in SecurityCenterEntry.allCases {
            XCTAssertFalse(entry.title.isEmpty, "\(entry) title must not be empty")
        }
    }

    func test_allEntries_haveNonEmptySystemImages() {
        for entry in SecurityCenterEntry.allCases {
            XCTAssertFalse(entry.systemImage.isEmpty, "\(entry) systemImage must not be empty")
        }
    }

    func test_entryDocumentTab_matchesSidebarNodeTab() {
        for entry in SecurityCenterEntry.allCases {
            let entryTab = entry.documentTab(clusterId: testClusterId)
            let nodeTab = entry.sidebarNode.toDocumentTab(clusterId: testClusterId)
            XCTAssertEqual(entryTab, nodeTab,
                           "SecurityCenterEntry.\(entry).documentTab must match its SidebarNode tab")
        }
    }

    // MARK: DocumentTab stable identity

    func test_securityTabIds_areDistinct() {
        let ids = [
            DocumentTab.securityOverview(clusterId: testClusterId).id,
            DocumentTab.securityImages(clusterId: testClusterId).id,
            DocumentTab.securityResources(clusterId: testClusterId).id,
            DocumentTab.securityRoles(clusterId: testClusterId).id,
        ]
        XCTAssertEqual(Set(ids).count, ids.count, "each security tab variant must have a unique id")
    }

    func test_securityTabIds_areDeterministic() {
        let tab = DocumentTab.securityImages(clusterId: testClusterId)
        XCTAssertEqual(tab.id, tab.id, "tab id must be stable across invocations")
    }

    // MARK: SecurityCenterDisclosureState

    func test_defaultDisclosureState_isExpanded() {
        XCTAssertTrue(SecurityCenterDisclosureState.default.isExpanded)
    }

    func test_disclosureState_roundtripsCodable() throws {
        let original = SecurityCenterDisclosureState(isExpanded: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SecurityCenterDisclosureState.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: SidebarTree standard categories

    func test_standardCategories_containsSecurityCenter() {
        let categories = SidebarTree.standardCategories()
        XCTAssertTrue(categories.contains(.securityCenter),
                      "securityCenter must appear in standardCategories")
    }

    func test_standardCategories_securityCenterIsAfterCustomResources() {
        let categories = SidebarTree.standardCategories()
        guard let crIndex = categories.firstIndex(of: .customResources),
              let scIndex = categories.firstIndex(of: .securityCenter)
        else {
            XCTFail("Both customResources and securityCenter must be in standardCategories")
            return
        }
        XCTAssertGreaterThan(scIndex, crIndex,
                             "securityCenter must appear after customResources per ADR-0068")
    }
}

// MARK: - Helpers

private let testClusterId = ClusterId("adr-0068-test-cluster")
