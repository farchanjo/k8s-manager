// Tests/AppShellTests/ClusterStripActorTests.swift — app_shell bounded context
// DDD role: BehaviouralSpecification (actor lifecycle + persistence coverage)
// ADR ref: ADR-0051

import XCTest
@testable import AppShell
import SharedKernel

// MARK: - ClusterStripActorTests

final class ClusterStripActorTests: XCTestCase {

    // MARK: Helpers

    /// Creates an actor backed by a temporary file under the system temp dir.
    private func makeActor() -> ClusterStripActor {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        return ClusterStripActor(persistenceURL: url)
    }

    private func id(_ raw: String) -> ClusterId { ClusterId(raw) }

    // MARK: - Test: pin adds to list with correct order

    func test_pin_addsWithCorrectOrder() async throws {
        let actor = makeActor()
        try await actor.pin(clusterId: id("c1"), displayName: "prod-aks")
        try await actor.pin(clusterId: id("c2"), displayName: "staging-eks")

        let pins = await actor.pins
        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(pins[0].clusterId, id("c1"))
        XCTAssertEqual(pins[0].order, 0)
        XCTAssertEqual(pins[1].clusterId, id("c2"))
        XCTAssertEqual(pins[1].order, 1)
    }

    // MARK: - Test: duplicate pin is idempotent

    func test_pin_duplicateIsIdempotent() async throws {
        let actor = makeActor()
        try await actor.pin(clusterId: id("c1"), displayName: "prod-aks")
        try await actor.pin(clusterId: id("c1"), displayName: "prod-aks")

        let pins = await actor.pins
        XCTAssertEqual(pins.count, 1, "Duplicate pin must not be added")
    }

    // MARK: - Test: unpin removes and normalises order

    func test_unpin_removesAndNormalisesOrder() async throws {
        let actor = makeActor()
        try await actor.pin(clusterId: id("alpha"), displayName: "Alpha")
        try await actor.pin(clusterId: id("beta"), displayName: "Beta")
        try await actor.pin(clusterId: id("gamma"), displayName: "Gamma")

        await actor.unpin(id("beta"))

        let pins = await actor.pins
        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(pins[0].clusterId, id("alpha"))
        XCTAssertEqual(pins[0].order, 0)
        XCTAssertEqual(pins[1].clusterId, id("gamma"))
        XCTAssertEqual(pins[1].order, 1)
    }

    // MARK: - Test: reorder preserves identities

    func test_reorder_preservesIdentitiesAndUpdatesOrder() async throws {
        let actor = makeActor()
        try await actor.pin(clusterId: id("alpha"), displayName: "Alpha")
        try await actor.pin(clusterId: id("beta"), displayName: "Beta")
        try await actor.pin(clusterId: id("gamma"), displayName: "Gamma")

        await actor.reorder([id("gamma"), id("alpha"), id("beta")])

        let pins = await actor.pins
        XCTAssertEqual(pins.map(\.clusterId), [id("gamma"), id("alpha"), id("beta")])
        XCTAssertEqual(pins.map(\.order), [0, 1, 2])
    }

    // MARK: - Test: save + load roundtrip

    func test_saveLoad_roundtrip() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }

        let actor1 = ClusterStripActor(persistenceURL: url)
        try await actor1.pin(clusterId: id("r1"), displayName: "Round Trip One")
        try await actor1.pin(clusterId: id("r2"), displayName: "Round Trip Two")
        await actor1.setActive(id("r2"))
        // Give debounce time to flush.
        try await Task.sleep(nanoseconds: 700_000_000)

        let actor2 = ClusterStripActor(persistenceURL: url)
        try await actor2.loadFromDisk()

        let pins = await actor2.pins
        let active = await actor2.activeClusterId
        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(pins[0].clusterId, id("r1"))
        XCTAssertEqual(pins[1].clusterId, id("r2"))
        XCTAssertEqual(active, id("r2"))
    }

    // MARK: - Test: deterministic color generation

    func test_deterministic_colorIsStableAcrossInstances() {
        let clusterId = ClusterId("01900000-0000-7000-8000-000000000010")
        let color1 = ClusterAvatarColor.deterministic(for: clusterId)
        let color2 = ClusterAvatarColor.deterministic(for: clusterId)
        XCTAssertEqual(color1, color2, "Color must be deterministic for the same clusterId")
    }

    func test_deterministic_colorDiffersForDifferentIds() {
        // Statistically extremely unlikely that all 8 IDs hash to the same index.
        let ids = (1...8).map { ClusterId("id-\($0)") }
        let colors = ids.map { ClusterAvatarColor.deterministic(for: $0) }
        // At least 2 distinct colors across 8 distinct IDs.
        XCTAssertGreaterThan(Set(colors).count, 1)
    }

    // MARK: - Test: max pins limit

    func test_pin_throwsWhenExceedingMaxPins() async throws {
        let actor = makeActor()
        for i in 0..<16 {
            try await actor.pin(clusterId: id("c\(i)"), displayName: "Cluster \(i)")
        }
        await XCTAssertAsyncThrowsError(
            try await actor.pin(clusterId: id("c16"), displayName: "One Too Many")
        ) { error in
            XCTAssertTrue(error is ClusterStripError)
        }
    }
}

// MARK: - XCTAssertAsyncThrowsError helper

private func XCTAssertAsyncThrowsError<T: Sendable>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown \(message)", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
