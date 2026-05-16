// Tests/LocalPersistenceTests/StateRestorationTests.swift
// XCTest suite for StateRestoration domain types.
//
// Coverage:
//   1. Codable roundtrip — StateRestoration, RestorationManifest,
//      RestorationPrompt survive JSON encode/decode with snake_case keys.
//   2. Manifest invariant validation — schemaVersion < 1 fails isValid.
//   3. StateRestoration aggregate validity — propagates manifest and prompt
//      invariants correctly.

import XCTest
@testable import LocalPersistence

// MARK: - StateRestorationTests

final class StateRestorationTests: XCTestCase {

    // MARK: Helpers

    private let iso8601: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var fixedDate: Date { iso8601.date(from: "2026-01-01T00:00:00Z")! }

    private func makeManifest(schemaVersion: Int = 1) -> RestorationManifest {
        RestorationManifest(
            schemaVersion: schemaVersion,
            lastClosedAt: fixedDate,
            activeContextId: UUID(uuidString: "018e4f3a-0000-7000-8000-000000000001"),
            openTerminalSessions: [UUID(uuidString: "018e4f3a-0000-7000-8000-000000000002")!],
            openPortForwards: [],
            pinnedClusterContextIds: [UUID(uuidString: "018e4f3a-0000-7000-8000-000000000003")!],
            chatSessions: [],
            dashboardCustomLayouts: ["global": "{\"layout\":\"grid\"}"]
        )
    }

    private func makePrompt(accepted: Bool = true) -> RestorationPrompt {
        RestorationPrompt(
            kind: .reopenTerminals,
            payload: #"{"count":1,"sessionIds":["018e4f3a-0000-7000-8000-000000000002"]}"#,
            accepted: accepted,
            presentedAt: fixedDate
        )
    }

    // MARK: Test 1 — Codable roundtrip

    func test_codableRoundtrip_preservesAllFields() throws {
        let manifest = makeManifest()
        let prompt = makePrompt()
        let restoration = StateRestoration(manifest: manifest, pendingPrompts: [prompt])

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(restoration)
        let decoded = try decoder.decode(StateRestoration.self, from: data)

        XCTAssertEqual(decoded.manifest.schemaVersion, 1)
        XCTAssertEqual(decoded.manifest.openTerminalSessions.count, 1)
        XCTAssertEqual(decoded.manifest.pinnedClusterContextIds.count, 1)
        XCTAssertEqual(decoded.manifest.dashboardCustomLayouts["global"], "{\"layout\":\"grid\"}")
        XCTAssertEqual(decoded.pendingPrompts.count, 1)
        XCTAssertEqual(decoded.pendingPrompts[0].kind, .reopenTerminals)
        XCTAssertTrue(decoded.pendingPrompts[0].accepted)
        XCTAssertEqual(decoded.pendingPrompts[0].payload, prompt.payload)
    }

    // MARK: Test 2 — Manifest invariant validation

    func test_manifestSchemaVersion_zeroIsInvalid() {
        let manifest = makeManifest(schemaVersion: 0)
        XCTAssertFalse(manifest.isValid)
    }

    func test_manifestSchemaVersion_oneIsValid() {
        let manifest = makeManifest(schemaVersion: 1)
        XCTAssertTrue(manifest.isValid)
    }

    func test_prompt_emptyPayload_isInvalid() {
        let prompt = RestorationPrompt(
            kind: .migrateStoragePath,
            payload: "",
            accepted: false,
            presentedAt: fixedDate
        )
        XCTAssertFalse(prompt.isValid)
    }

    // MARK: Test 3 — StateRestoration aggregate validity

    func test_stateRestoration_invalidManifest_propagatesInvalidity() {
        let badManifest = makeManifest(schemaVersion: 0)
        let restoration = StateRestoration(manifest: badManifest, pendingPrompts: [])
        XCTAssertFalse(restoration.isValid)
    }

    func test_stateRestoration_validManifestAndEmptyPrompts_isValid() {
        let restoration = StateRestoration(manifest: makeManifest(), pendingPrompts: [])
        XCTAssertTrue(restoration.isValid)
    }

    func test_stateRestoration_validManifestWithInvalidPrompt_propagatesInvalidity() {
        let badPrompt = RestorationPrompt(
            kind: .reopenPortForwards,
            payload: "",       // violates CUE invariant
            accepted: true,
            presentedAt: fixedDate
        )
        let restoration = StateRestoration(manifest: makeManifest(), pendingPrompts: [badPrompt])
        XCTAssertFalse(restoration.isValid)
    }
}
