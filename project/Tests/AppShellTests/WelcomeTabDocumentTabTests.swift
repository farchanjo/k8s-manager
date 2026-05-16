// Tests/AppShellTests/WelcomeTabDocumentTabTests.swift
// Target: AppShellTests
// Coverage: ADR-0054 DocumentTab.welcome value-object invariants

import XCTest
@testable import AppShell
import SharedKernel

final class WelcomeTabDocumentTabTests: XCTestCase {

    // MARK: - Identity stability

    func test_welcomeTab_idIsStableAcrossInvocations() {
        XCTAssertEqual(DocumentTab.welcome.id, DocumentTab.welcome.id)
    }

    func test_welcomeTab_idIsDistinctFromOtherKinds() {
        let cid = ClusterId("c1")
        XCTAssertNotEqual(DocumentTab.welcome.id, DocumentTab.overview(clusterId: cid).id)
        XCTAssertNotEqual(DocumentTab.welcome.id, DocumentTab.applications(clusterId: cid).id)
    }

    // MARK: - Workspace-scoped contract

    func test_welcomeTab_isWorkspaceScoped() {
        XCTAssertTrue(DocumentTab.welcome.isWorkspaceScoped)
    }

    func test_welcomeTab_carriesNoClusterId() {
        XCTAssertNil(DocumentTab.welcome.clusterId)
    }

    func test_otherTabs_areNotWorkspaceScoped() {
        let cid = ClusterId("c1")
        XCTAssertFalse(DocumentTab.overview(clusterId: cid).isWorkspaceScoped)
        XCTAssertFalse(DocumentTab.nodes(clusterId: cid).isWorkspaceScoped)
        XCTAssertFalse(DocumentTab.applications(clusterId: cid).isWorkspaceScoped)
    }

    // MARK: - Close-button exemption

    func test_welcomeTab_isNotCloseable() {
        XCTAssertFalse(DocumentTab.welcome.isCloseable)
    }

    func test_otherTabs_areCloseable() {
        let cid = ClusterId("c1")
        XCTAssertTrue(DocumentTab.overview(clusterId: cid).isCloseable)
        XCTAssertTrue(DocumentTab.nodes(clusterId: cid).isCloseable)
    }

    // MARK: - Presentation

    func test_welcomeTab_titleIsWelcome() {
        XCTAssertEqual(DocumentTab.welcome.title, "Welcome")
    }

    func test_welcomeTab_iconIsHandWave() {
        XCTAssertEqual(DocumentTab.welcome.systemImage, "hand.wave")
    }

    // MARK: - Codable round-trip

    func test_welcomeTab_codableRoundTrip_preservesIdentity() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(DocumentTab.welcome)
        let decoded = try decoder.decode(DocumentTab.self, from: data)

        if case .welcome = decoded {
            XCTAssertEqual(decoded.id, DocumentTab.welcome.id)
        } else {
            XCTFail("Decoded value must be .welcome — got \(decoded)")
        }
    }

    func test_welcomeTab_codable_encodesWithoutClusterId() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(DocumentTab.welcome)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["type"] as? String, "welcome")
        XCTAssertNil(json["clusterId"], "welcome payload must not carry a clusterId")
    }
}
