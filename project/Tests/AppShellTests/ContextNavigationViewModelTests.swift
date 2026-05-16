// Tests/AppShellTests/ContextNavigationViewModelTests.swift
// Coverage: ContextNavigationViewModel sidebar load flows.

import XCTest
import Dependencies
@testable import AppShell
import ContextNavigation
import SharedKernel

// MARK: - ContextNavigationViewModelTests

@MainActor
final class ContextNavigationViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = ContextNavigationViewModel()
        XCTAssertTrue(sut.sidebar.isIdle)
    }

    // MARK: loadActiveContext — success

    func test_loadActiveContext_setsSuccessOnEmptySidebar() async {
        let expected = SidebarReadModel(pinned: [], recents: [])
        let fakePort = FakeSidebarReadModelPort(result: expected)

        await withDependencies {
            $0.sidebarReadModel = fakePort
        } operation: {
            let sut = ContextNavigationViewModel()
            await sut.loadActiveContext()
            XCTAssertEqual(sut.sidebar.value?.pinned.count, 0)
            XCTAssertEqual(sut.sidebar.value?.recents.count, 0)
        }
    }

    func test_loadActiveContext_setsPinnedAndRecents() async {
        let pin = PinnedContext(
            contextId: ContextId("prod"),
            pinnedAtRFC3339: "2026-01-01T00:00:00Z",
            displayOrder: 0
        )
        let recent = RecentContextEntry(
            contextId: ContextId("staging"),
            displayName: "staging",
            lastUsedRFC3339: "2026-01-02T00:00:00Z",
            useCount: 3
        )
        let expected = SidebarReadModel(pinned: [pin], recents: [recent])
        let fakePort = FakeSidebarReadModelPort(result: expected)

        await withDependencies {
            $0.sidebarReadModel = fakePort
        } operation: {
            let sut = ContextNavigationViewModel()
            await sut.loadActiveContext()
            XCTAssertEqual(sut.sidebar.value?.pinned.count, 1)
            XCTAssertEqual(sut.sidebar.value?.recents.first?.displayName, "staging")
        }
    }

    // MARK: loadActiveContext — failure

    func test_loadActiveContext_setsFailureOnError() async {
        let fakePort = FakeSidebarReadModelPort(error: SidebarReadModelError.unimplemented)

        await withDependencies {
            $0.sidebarReadModel = fakePort
        } operation: {
            let sut = ContextNavigationViewModel()
            await sut.loadActiveContext()
            XCTAssertNotNil(sut.sidebar.error)
            XCTAssertNil(sut.sidebar.value)
        }
    }

    // MARK: Retry

    func test_loadActiveContext_retryTransitionsFromFailureToSuccess() async {
        let expected = SidebarReadModel(pinned: [], recents: [])
        let failing = FakeSidebarReadModelPort(error: SidebarReadModelError.unimplemented)
        let succeeding = FakeSidebarReadModelPort(result: expected)

        await withDependencies {
            $0.sidebarReadModel = failing
        } operation: {
            let sut = ContextNavigationViewModel()
            await sut.loadActiveContext()
            XCTAssertNotNil(sut.sidebar.error)
        }

        await withDependencies {
            $0.sidebarReadModel = succeeding
        } operation: {
            let sut = ContextNavigationViewModel()
            await sut.loadActiveContext()
            XCTAssertNotNil(sut.sidebar.value)
        }
    }
}

// MARK: - Test doubles

private struct FakeSidebarReadModelPort: SidebarReadModelPort {
    let stubbedResult: SidebarReadModel?
    let stubbedError: Error?

    init(result: SidebarReadModel? = nil, error: Error? = nil) {
        self.stubbedResult = result
        self.stubbedError = error
    }

    func currentSidebar() async throws -> SidebarReadModel {
        if let error = stubbedError { throw error }
        return stubbedResult!
    }

    func watchSidebar() -> AsyncThrowingStream<SidebarReadModel, Error> {
        AsyncThrowingStream { continuation in
            if let error = stubbedError {
                continuation.finish(throwing: error)
            } else if let result = stubbedResult {
                continuation.yield(result)
                continuation.finish()
            }
        }
    }
}
