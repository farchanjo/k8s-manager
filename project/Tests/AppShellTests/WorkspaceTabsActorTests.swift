// Tests/AppShellTests/WorkspaceTabsActorTests.swift
// Target: AppShellTests
// Coverage: ADR-0054 workspace tab invariants
//
// Verifies:
// 1. Welcome tab is present at initialisation (single-instance, position 0).
// 2. Calling `openTab(.welcome)` on an actor that already contains it does
//    not create a duplicate — instead focuses the existing instance.
// 3. `loadFromDisk` injects Welcome when the persisted payload omits it
//    (migration safety from a pre-ADR-0054 build).
// 4. `loadFromDisk` preserves Welcome when the payload includes it.
// 5. Cold-launch with no persistence file keeps the default Welcome state.

import XCTest
@testable import AppShell
import SharedKernel

final class WorkspaceTabsActorTests: XCTestCase {

    // MARK: Helpers

    private func makeActor(persistenceURL: URL) -> WorkspaceTabsActor {
        WorkspaceTabsActor(persistenceURL: persistenceURL)
    }

    private var tmpFile: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString)/workspace-tabs.json")
    }

    /// Writes `payload` to `url` as JSON, creating intermediate directories.
    private func writeJSON<T: Encodable>(_ payload: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Default state

    func test_initialState_containsWelcomeAtPositionZero() async {
        let sut = makeActor(persistenceURL: tmpFile)

        let tabs = await sut.tabs
        let activeId = await sut.activeTabId

        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first, .welcome)
        XCTAssertEqual(activeId, DocumentTab.welcome.id)
    }

    // MARK: - Single-instance enforcement

    func test_openTab_welcomeDuplicate_doesNotCreateSecondInstance() async {
        let sut = makeActor(persistenceURL: tmpFile)

        await sut.openTab(.welcome)
        await sut.openTab(.welcome)

        let tabs = await sut.tabs
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first, .welcome)
    }

    // MARK: - Non-workspace tabs are rejected

    func test_openTab_nonWorkspaceTab_isIgnored() async {
        let sut = makeActor(persistenceURL: tmpFile)
        let clusterTab: DocumentTab = .overview(clusterId: ClusterId("c1"))

        await sut.openTab(clusterTab)

        let tabs = await sut.tabs
        XCTAssertEqual(tabs.count, 1, "Cluster tabs must not enter the workspace actor")
        XCTAssertEqual(tabs.first, .welcome)
    }

    // MARK: - Migration: Welcome injected when payload omits it

    func test_loadFromDisk_payloadWithoutWelcome_injectsWelcomeAtPositionZero() async throws {
        let url = tmpFile

        // Simulate a payload from a pre-ADR-0054 build: no welcome present.
        struct LegacyPayload: Codable {
            let tabs: [DocumentTab]
            let activeTabId: TabId?
        }
        let legacy = LegacyPayload(tabs: [], activeTabId: nil)
        try writeJSON(legacy, to: url)

        let sut = makeActor(persistenceURL: url)
        try await sut.loadFromDisk()

        let tabs = await sut.tabs
        let activeId = await sut.activeTabId

        XCTAssertEqual(tabs.first, .welcome, "Welcome must be injected at position 0")
        XCTAssertEqual(activeId, DocumentTab.welcome.id)
    }

    // MARK: - Welcome preserved when payload includes it

    func test_loadFromDisk_payloadWithWelcome_preservesWelcome() async throws {
        let url = tmpFile

        struct PersistedPayload: Codable {
            let tabs: [DocumentTab]
            let activeTabId: TabId?
        }
        let payload = PersistedPayload(
            tabs: [.welcome],
            activeTabId: DocumentTab.welcome.id
        )
        try writeJSON(payload, to: url)

        let sut = makeActor(persistenceURL: url)
        try await sut.loadFromDisk()

        let tabs = await sut.tabs
        let activeId = await sut.activeTabId

        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first, .welcome)
        XCTAssertEqual(activeId, DocumentTab.welcome.id)
    }

    // MARK: - Cold launch with missing file

    func test_loadFromDisk_missingFile_keepsDefaultWelcomeState() async throws {
        let url = tmpFile
        let sut = makeActor(persistenceURL: url)

        // File does not exist — load should swallow absence and keep defaults.
        try await sut.loadFromDisk()

        let tabs = await sut.tabs
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first, .welcome)
    }

    // MARK: - Focus helpers

    func test_focusWelcome_setsActiveTabIdToWelcome() async {
        let sut = makeActor(persistenceURL: tmpFile)

        await sut.focusWelcome()

        let activeId = await sut.activeTabId
        XCTAssertEqual(activeId, DocumentTab.welcome.id)
    }

    // MARK: - containsWelcome predicate

    func test_containsWelcome_defaultsToTrue() async {
        let sut = makeActor(persistenceURL: tmpFile)
        let contains = await sut.containsWelcome
        XCTAssertTrue(contains)
    }
}
