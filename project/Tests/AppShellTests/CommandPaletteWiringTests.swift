// Tests/AppShellTests/CommandPaletteWiringTests.swift
// Coverage: CommandPaletteViewModel dynamic command loading from ContextRepositoryPort.

import XCTest
import Dependencies
@testable import AppShell
import ContextNavigation
import SharedKernel

// MARK: - CommandPaletteWiringTests

@MainActor
final class CommandPaletteWiringTests: XCTestCase {

    // MARK: Test 1 — context-switch commands generated per recent context entry

    func test_loadCommands_buildsOneSwitchEntryPerRecentContext() async {
        let entries = [
            RecentContextEntry(
                contextId: ContextId("prod"),
                displayName: "production",
                lastUsedRFC3339: "2026-01-01T00:00:00Z",
                useCount: 5
            ),
            RecentContextEntry(
                contextId: ContextId("stg"),
                displayName: "staging",
                lastUsedRFC3339: "2026-01-02T00:00:00Z",
                useCount: 2
            ),
        ]
        let repo = FakePaletteContextRepo(entries: entries)

        await withDependencies {
            $0.contextRepository = repo
        } operation: {
            let sut = CommandPaletteViewModel()
            await sut.loadCommands()
            sut.open()
            let switchIds = sut.results.filter { $0.id.hasPrefix("switch-") }
            XCTAssertEqual(switchIds.count, 2,
                "Expected one switch-context command per recent entry (2 entries)")
            XCTAssertTrue(
                switchIds.contains(where: { $0.title.contains("production") }),
                "Expected a 'Switch context to production' entry"
            )
            XCTAssertTrue(
                switchIds.contains(where: { $0.title.contains("staging") }),
                "Expected a 'Switch context to staging' entry"
            )
        }
    }

    // MARK: Test 2 — static commands always present regardless of context data

    func test_loadCommands_alwaysIncludesStaticActions() async {
        let repo = FakePaletteContextRepo(entries: [])

        await withDependencies {
            $0.contextRepository = repo
        } operation: {
            let sut = CommandPaletteViewModel()
            await sut.loadCommands()
            sut.open()
            let ids = Set(sut.results.map(\.id))
            XCTAssertTrue(ids.contains("refresh"),          "Expected 'refresh' command")
            XCTAssertTrue(ids.contains("quit"),             "Expected 'quit' command")
            XCTAssertTrue(ids.contains("open-preferences"), "Expected 'open-preferences' command")
        }
    }

    // MARK: Test 3 — context repo failure falls back to static commands only

    func test_loadCommands_repoError_fallsBackToStaticCommands() async {
        let repo = FakePaletteContextRepo(error: ContextRepositoryError.unimplemented)

        await withDependencies {
            $0.contextRepository = repo
        } operation: {
            let sut = CommandPaletteViewModel()
            await sut.loadCommands()
            sut.open()
            // No switch-context entries when repo fails.
            let switchIds = sut.results.filter { $0.id.hasPrefix("switch-") }
            XCTAssertEqual(switchIds.count, 0, "No switch entries expected on repo error")
            // Static commands should still be present.
            XCTAssertFalse(sut.results.isEmpty, "Static commands should still be present")
        }
    }
}

// MARK: - Test double

private struct FakePaletteContextRepo: ContextRepositoryPort {
    let stubbedEntries: [RecentContextEntry]
    let stubbedError: Error?

    init(entries: [RecentContextEntry]) {
        self.stubbedEntries = entries
        self.stubbedError = nil
    }

    init(error: Error) {
        self.stubbedEntries = []
        self.stubbedError = error
    }

    func loadRecentWindow() async throws -> RecentContextWindow {
        if let error = stubbedError { throw error }
        return RecentContextWindow(entries: stubbedEntries)
    }

    func saveRecentWindow(_ window: RecentContextWindow) async throws {}

    func loadPinnedContexts() async throws -> [PinnedContext] { [] }

    func pin(_ context: PinnedContext) async throws {}

    func unpin(contextId: ContextId) async throws {}

    func loadLastActiveContext() async throws -> ActiveContext? { nil }

    func saveLastActiveContext(_ context: ActiveContext) async throws {}
}
