// Tests/AppShellTests/CommandPaletteViewModelTests.swift
// Target: AppShellTests
// ADR ref: ADR-0023 (command palette — fuzzy match, selection, keyboard navigation)
import XCTest
@testable import AppShell

@MainActor
final class CommandPaletteViewModelTests: XCTestCase {

    // MARK: Helpers

    private func makeViewModel() -> CommandPaletteViewModel {
        let catalog: [Command] = [
            Command(id: "clusters",  title: "View Clusters",   subtitle: nil,        systemImage: "cube.transparent")    { },
            Command(id: "resources", title: "View Resources",  subtitle: "Browse",   systemImage: "list.bullet.rectangle") { },
            Command(id: "settings",  title: "Open Settings",   subtitle: nil,        systemImage: "gear")                 { },
            Command(id: "terminal",  title: "New Terminal Tab", subtitle: nil,        systemImage: "terminal")             { },
            Command(id: "refresh",   title: "Refresh View",    subtitle: "Reload",   systemImage: "arrow.clockwise")      { },
        ]
        return CommandPaletteViewModel(catalog: catalog)
    }

    // MARK: Test 1 — filter: exact substring match

    /// Querying "Settings" returns only the Settings command.
    func test_filter_exactSubstringMatch() {
        let vm = makeViewModel()
        vm.open()
        vm.query = "Settings"
        // Synchronous path (≤ 3 chars uses sync; "Settings" is > 3 so we wait a tick).
        let exp = expectation(description: "filter settles")
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            XCTAssertFalse(vm.results.isEmpty, "Expected at least one result for 'Settings'")
            XCTAssertTrue(
                vm.results.contains(where: { $0.id == "settings" }),
                "Expected 'settings' command in results for query 'Settings'"
            )
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }

    // MARK: Test 2 — filter: short query uses synchronous path

    /// A 2-character query ("Re") matches "View Resources" and "Refresh View" synchronously.
    func test_filter_shortQuerySynchronous() {
        let vm = makeViewModel()
        vm.open()
        vm.query = "Re"
        // No async needed — short query (≤ 3) runs synchronously.
        let matchedIds = Set(vm.results.map(\.id))
        XCTAssertTrue(
            matchedIds.contains("resources") || matchedIds.contains("refresh"),
            "Expected 'resources' or 'refresh' for query 'Re', got: \(matchedIds)"
        )
    }

    // MARK: Test 3 — filter: empty query returns full catalog

    /// Clearing the query after a search restores the full catalog.
    func test_filter_emptyQueryReturnsFullCatalog() {
        let vm = makeViewModel()
        vm.open()
        vm.query = "xyz"
        vm.query = ""
        XCTAssertEqual(vm.results.count, 5, "Empty query must restore the full catalog (5 items)")
    }

    // MARK: Test 4 — keyboard navigation wraps correctly

    /// `moveCursorDown()` wraps from last to first; `moveCursorUp()` wraps from first to last.
    func test_keyboardNavigation_wrapsAtBoundaries() {
        let vm = makeViewModel()
        vm.open()   // results = full catalog (5 items)

        // Move down past end → should wrap to 0.
        for _ in 0..<5 { vm.moveCursorDown() }
        XCTAssertEqual(vm.selectedIndex, 0, "Cursor should wrap to 0 after 5 down moves on 5 items")

        // Move up from 0 → should wrap to last.
        vm.moveCursorUp()
        XCTAssertEqual(vm.selectedIndex, 4, "Cursor should wrap to last item (4) on up from 0")
    }

    // MARK: Test 5 — executeSelected dismisses palette

    /// Executing the selected command dismisses the overlay.
    func test_executeSelected_dismissesPalette() {
        var actionCalled = false
        let catalog = [Command(
            id: "test-cmd",
            title: "Test Command",
            subtitle: nil,
            systemImage: "star"
        ) { actionCalled = true }]
        let vm = CommandPaletteViewModel(catalog: catalog)
        vm.open()
        XCTAssertTrue(vm.isVisible)
        // selectAndExecute(index:) both sets selectedIndex and calls executeSelected.
        vm.selectAndExecute(index: 0)
        XCTAssertFalse(vm.isVisible, "Palette must be dismissed after executeSelected()")
        XCTAssertTrue(actionCalled, "Command action must be invoked by executeSelected()")
    }
}

// MARK: - Levenshtein unit tests (nonisolated utility)

final class LevenshteinTests: XCTestCase {

    func test_levenshtein_identicalStrings() {
        XCTAssertEqual(CommandPaletteViewModel.levenshtein("abc", "abc"), 0)
    }

    func test_levenshtein_emptyInputs() {
        XCTAssertEqual(CommandPaletteViewModel.levenshtein("", "abc"), 3)
        XCTAssertEqual(CommandPaletteViewModel.levenshtein("abc", ""), 3)
    }

    func test_isSubsequence_positive() {
        XCTAssertTrue(CommandPaletteViewModel.isSubsequence("po", in: "pods"))
        XCTAssertTrue(CommandPaletteViewModel.isSubsequence("dep", in: "deployment"))
    }

    func test_isSubsequence_negative() {
        XCTAssertFalse(CommandPaletteViewModel.isSubsequence("xyz", in: "pods"))
    }
}
