// Tests/LocalPersistenceTests/OperatorPreferencesPortTests.swift
// XCTest suite for OperatorPreferencesPort.
//
// Coverage:
//   1. Unimplemented default — `DependencyValues.operatorPreferences` testValue
//      throws `.unimplemented` for both load and save.
//   2. Override pattern — replacing the dependency in `withDependencies` causes
//      calls to reach the stub instead of the sentinel.

import XCTest
import Dependencies
@testable import LocalPersistence

// MARK: - OperatorPreferencesPortTests

final class OperatorPreferencesPortTests: XCTestCase {

    // MARK: Test 1 — Unimplemented default throws

    func test_unimplementedDefault_loadPreferences_throws() async {
        await withDependencies { _ in } operation: {
            @Dependency(\.operatorPreferences) var port
            do {
                _ = try await port.loadPreferences()
                XCTFail("Expected OperatorPreferencesError.unimplemented to be thrown")
            } catch OperatorPreferencesError.unimplemented {
                // pass — sentinel matched
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_unimplementedDefault_savePreferences_throws() async {
        await withDependencies { _ in } operation: {
            @Dependency(\.operatorPreferences) var port
            do {
                try await port.savePreferences(OperatorPreferences())
                XCTFail("Expected OperatorPreferencesError.unimplemented to be thrown")
            } catch OperatorPreferencesError.unimplemented {
                // pass — sentinel matched
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    // MARK: Test 2 — Override pattern

    /// Verifies that overriding `\.operatorPreferences` inside
    /// `withDependencies` delivers calls to the stub, exercising the full
    /// pointfreeco/swift-dependencies override pattern used in app_shell tests.
    func test_overridePattern_stubReceivesCalls() async throws {
        let stub = RecordingPreferencesPort()
        let saved = OperatorPreferences(
            theme: .dark,
            locale: AppLocale(bcp47: "pt-BR"),
            sidebarLayout: .autoCollapse,
            recentResources: []
        )

        try await withDependencies { values in
            values.operatorPreferences = stub
        } operation: {
            @Dependency(\.operatorPreferences) var port
            try await port.savePreferences(saved)
            let loaded = try await port.loadPreferences()
            XCTAssertEqual(loaded.theme, .dark)
            XCTAssertEqual(loaded.sidebarLayout, .autoCollapse)
            XCTAssertEqual(loaded.locale?.bcp47, "pt-BR")
        }

        XCTAssertEqual(stub.saveCallCount, 1)
        XCTAssertEqual(stub.loadCallCount, 1)
    }
}

// MARK: - RecordingPreferencesPort

/// In-memory stub that records method call counts and echoes back the last
/// saved preferences on load.
private final class RecordingPreferencesPort: OperatorPreferencesPort, @unchecked Sendable {

    private var stored: OperatorPreferences = OperatorPreferences()
    private(set) var saveCallCount = 0
    private(set) var loadCallCount = 0

    func loadPreferences() async throws -> OperatorPreferences {
        loadCallCount += 1
        return stored
    }

    func savePreferences(_ preferences: OperatorPreferences) async throws {
        saveCallCount += 1
        stored = preferences
    }
}
