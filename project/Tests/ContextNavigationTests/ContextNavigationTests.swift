// ContextNavigationTests.swift — context_navigation bounded context
// XCTest coverage: domain types, domain services, DI port overrides.

import XCTest
import Dependencies
@testable import ContextNavigation
import SharedKernel

// MARK: - ActiveContextTests

final class ActiveContextTests: XCTestCase {
    func test_activeContext_construction_defaults() {
        let ctx = ActiveContext()
        XCTAssertNil(ctx.contextId)
        XCTAssertNil(ctx.selectedAtRFC3339)
        XCTAssertNil(ctx.selectedBy)
    }

    func test_activeContext_with_contextId_roundtrips() throws {
        let id = ContextId("test-context")
        let ctx = ActiveContext(
            contextId: id,
            selectedAtRFC3339: "2024-01-01T00:00:00Z",
            selectedBy: .user
        )
        XCTAssertEqual(ctx.contextId, id)
        XCTAssertEqual(ctx.selectedBy, .user)
        XCTAssertEqual(ctx.selectedAtRFC3339, "2024-01-01T00:00:00Z")
    }

    func test_activeContext_codable_roundtrip() throws {
        let ctx = ActiveContext(
            contextId: ContextId("my-ctx"),
            selectedAtRFC3339: "2024-06-15T12:00:00Z",
            selectedBy: .restored
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(ActiveContext.self, from: data)
        XCTAssertEqual(ctx, decoded)
    }

    func test_selectionOrigin_all_cases_rawValues() {
        XCTAssertEqual(SelectionOrigin.user.rawValue, "user")
        XCTAssertEqual(SelectionOrigin.restored.rawValue, "restored")
        XCTAssertEqual(SelectionOrigin.fallback.rawValue, "fallback")
    }
}

// MARK: - RecentContextTests

final class RecentContextTests: XCTestCase {
    func test_recentContextEntry_useCount_minimum_one() {
        let entry = RecentContextEntry(
            contextId: ContextId("x"),
            displayName: "X Cluster",
            lastUsedRFC3339: "2024-01-01T00:00:00Z",
            useCount: 0
        )
        XCTAssertEqual(entry.useCount, 1)
    }

    func test_recentContextEntry_pinned_defaults_to_false() {
        let entry = RecentContextEntry(
            contextId: ContextId("y"),
            displayName: "Y",
            lastUsedRFC3339: "2024-01-01T00:00:00Z",
            useCount: 3
        )
        XCTAssertFalse(entry.pinned)
    }

    func test_recentContextWindow_maxEntries_clamped_to_minimum() {
        let window = RecentContextWindow(maxEntries: 2)
        XCTAssertEqual(window.maxEntries, 8)
    }

    func test_recentContextWindow_maxEntries_clamped_to_maximum() {
        let window = RecentContextWindow(maxEntries: 200)
        XCTAssertEqual(window.maxEntries, 64)
    }

    func test_recentContextWindow_default_max_is_32() {
        let window = RecentContextWindow()
        XCTAssertEqual(window.maxEntries, 32)
    }

    func test_recentContextEntry_codable_roundtrip() throws {
        let entry = RecentContextEntry(
            contextId: ContextId("kind-local"),
            displayName: "Local Kind",
            lastUsedRFC3339: "2024-03-10T08:00:00Z",
            useCount: 5,
            pinned: true
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(RecentContextEntry.self, from: data)
        XCTAssertEqual(entry, decoded)
    }

    func test_pinnedContext_displayOrder_minimum_zero() {
        let pin = PinnedContext(
            contextId: ContextId("p"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: -5
        )
        XCTAssertEqual(pin.displayOrder, 0)
    }

    func test_pinnedContext_codable_roundtrip() throws {
        let pin = PinnedContext(
            contextId: ContextId("prod"),
            pinnedAtRFC3339: "2024-06-01T00:00:00Z",
            displayOrder: 2
        )
        let data = try JSONEncoder().encode(pin)
        let decoded = try JSONDecoder().decode(PinnedContext.self, from: data)
        XCTAssertEqual(pin, decoded)
    }
}

// MARK: - ContextSwitcherTests

final class ContextSwitcherTests: XCTestCase {
    private let clock = FrozenClock(rfc3339: "2024-06-15T10:00:00Z")

    func test_switch_to_new_context_emits_event() {
        let initial = ActiveContext(contextId: ContextId("old"))
        let (next, event) = ContextSwitcher.select(
            current: initial,
            newContextId: ContextId("new"),
            origin: .user,
            clock: clock
        )
        XCTAssertEqual(next.contextId, ContextId("new"))
        XCTAssertEqual(next.selectedBy, .user)
        XCTAssertNotNil(event)
        XCTAssertEqual(event?.previous?.contextId, ContextId("old"))
        XCTAssertEqual(event?.next.contextId, ContextId("new"))
    }

    func test_switch_to_same_context_is_noop() {
        let initial = ActiveContext(contextId: ContextId("same"))
        let (next, event) = ContextSwitcher.select(
            current: initial,
            newContextId: ContextId("same"),
            origin: .user,
            clock: clock
        )
        XCTAssertEqual(next.id, initial.id)
        XCTAssertNil(event)
    }

    func test_switch_preserves_aggregate_id() {
        let initial = ActiveContext(contextId: ContextId("a"))
        let (next, _) = ContextSwitcher.select(
            current: initial,
            newContextId: ContextId("b"),
            origin: .fallback,
            clock: clock
        )
        XCTAssertEqual(next.id, initial.id)
    }

    func test_fallback_origin_is_recorded() {
        let initial = ActiveContext(contextId: ContextId("x"))
        let (next, _) = ContextSwitcher.select(
            current: initial,
            newContextId: ContextId("y"),
            origin: .fallback,
            clock: clock
        )
        XCTAssertEqual(next.selectedBy, .fallback)
    }
}

// MARK: - RecentsWindowUpdaterTests

final class RecentsWindowUpdaterTests: XCTestCase {
    private let clock = FrozenClock(rfc3339: "2024-06-15T10:00:00Z")

    func test_record_adds_new_entry_at_head() {
        let window = RecentContextWindow()
        let updated = RecentsWindowUpdater.record(
            in: window,
            contextId: ContextId("ctx-1"),
            displayName: "Cluster 1",
            clock: clock
        )
        XCTAssertEqual(updated.entries.first?.contextId, ContextId("ctx-1"))
        XCTAssertEqual(updated.entries.first?.useCount, 1)
    }

    func test_record_increments_use_count_on_reselection() {
        var window = RecentContextWindow()
        window = RecentsWindowUpdater.record(
            in: window, contextId: ContextId("ctx"), displayName: "C", clock: clock
        )
        window = RecentsWindowUpdater.record(
            in: window, contextId: ContextId("ctx"), displayName: "C", clock: clock
        )
        XCTAssertEqual(window.entries.first?.useCount, 2)
        XCTAssertEqual(window.entries.count, 1)
    }

    func test_record_promotes_existing_entry_to_head() {
        var window = RecentContextWindow()
        window = RecentsWindowUpdater.record(
            in: window, contextId: ContextId("first"), displayName: "First", clock: clock
        )
        window = RecentsWindowUpdater.record(
            in: window, contextId: ContextId("second"), displayName: "Second", clock: clock
        )
        window = RecentsWindowUpdater.record(
            in: window, contextId: ContextId("first"), displayName: "First", clock: clock
        )
        XCTAssertEqual(window.entries.first?.contextId, ContextId("first"))
    }

    func test_record_prunes_non_pinned_beyond_max() {
        var window = RecentContextWindow(maxEntries: 8)
        for i in 0..<10 {
            window = RecentsWindowUpdater.record(
                in: window,
                contextId: ContextId("ctx-\(i)"),
                displayName: "Ctx \(i)",
                clock: clock
            )
        }
        let nonPinned = window.entries.filter { !$0.pinned }
        XCTAssertEqual(nonPinned.count, 8)
    }

    func test_record_does_not_prune_pinned_entries() {
        let pinned = RecentContextEntry(
            contextId: ContextId("pinned"),
            displayName: "Pinned",
            lastUsedRFC3339: "2024-01-01T00:00:00Z",
            useCount: 1,
            pinned: true
        )
        var window = RecentContextWindow(maxEntries: 8, entries: [pinned])
        for i in 0..<10 {
            window = RecentsWindowUpdater.record(
                in: window,
                contextId: ContextId("ctx-\(i)"),
                displayName: "Ctx \(i)",
                clock: clock
            )
        }
        XCTAssertTrue(window.entries.contains { $0.contextId == ContextId("pinned") })
    }
}

// MARK: - ReadModelsTests

final class ReadModelsTests: XCTestCase {
    func test_sidebarReadModel_sorts_pinned_by_displayOrder() {
        let pins: [PinnedContext] = [
            PinnedContext(contextId: ContextId("b"), pinnedAtRFC3339: "2024-01-01T00:00:00Z", displayOrder: 2),
            PinnedContext(contextId: ContextId("a"), pinnedAtRFC3339: "2024-01-01T00:00:00Z", displayOrder: 0),
            PinnedContext(contextId: ContextId("c"), pinnedAtRFC3339: "2024-01-01T00:00:00Z", displayOrder: 1),
        ]
        let sidebar = SidebarReadModel(pinned: pins)
        XCTAssertEqual(sidebar.pinned.map(\.contextId), [
            ContextId("a"), ContextId("c"), ContextId("b"),
        ])
    }

    func test_activeContextReadModel_defaults_all_nil() {
        let model = ActiveContextReadModel()
        XCTAssertNil(model.contextId)
        XCTAssertNil(model.displayName)
        XCTAssertNil(model.selectedBy)
    }

    func test_activeContextReadModel_codable_roundtrip() throws {
        let model = ActiveContextReadModel(
            contextId: ContextId("prod"),
            displayName: "Production",
            selectedAtRFC3339: "2024-06-01T00:00:00Z",
            selectedBy: .user
        )
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(ActiveContextReadModel.self, from: data)
        XCTAssertEqual(model, decoded)
    }
}

// MARK: - ContextRepositoryPort DI tests

final class ContextRepositoryPortDITests: XCTestCase {
    func test_portCanBeOverridden_viaDependencies_loadRecentWindow() async throws {
        let fake = FakeContextRepository()

        try await withDependencies {
            $0.contextRepository = fake
        } operation: {
            @Dependency(\.contextRepository) var repo
            let window = try await repo.loadRecentWindow()
            XCTAssertTrue(window.entries.isEmpty)
            XCTAssertEqual(window.maxEntries, 32)
        }
    }

    func test_portCanBeOverridden_viaDependencies_saveAndLoadPin() async throws {
        let fake = FakeContextRepository()
        let pin = PinnedContext(
            contextId: ContextId("prod"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 0
        )

        try await withDependencies {
            $0.contextRepository = fake
        } operation: {
            @Dependency(\.contextRepository) var repo
            try await repo.pin(pin)
            let pins = try await repo.loadPinnedContexts()
            XCTAssertEqual(pins.count, 1)
            XCTAssertEqual(pins.first?.contextId, ContextId("prod"))
        }
    }

    func test_portCanBeOverridden_viaDependencies_unpin() async throws {
        let fake = FakeContextRepository()
        let pin = PinnedContext(
            contextId: ContextId("staging"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 1
        )

        try await withDependencies {
            $0.contextRepository = fake
        } operation: {
            @Dependency(\.contextRepository) var repo
            try await repo.pin(pin)
            try await repo.unpin(contextId: ContextId("staging"))
            let pins = try await repo.loadPinnedContexts()
            XCTAssertTrue(pins.isEmpty)
        }
    }

    func test_portCanBeOverridden_viaDependencies_lastActiveContext_nilOnStart() async throws {
        let fake = FakeContextRepository()

        try await withDependencies {
            $0.contextRepository = fake
        } operation: {
            @Dependency(\.contextRepository) var repo
            let loaded = try await repo.loadLastActiveContext()
            XCTAssertNil(loaded)
        }
    }

    func test_portCanBeOverridden_viaDependencies_saveAndLoadLastActive() async throws {
        let fake = FakeContextRepository()
        let active = ActiveContext(
            contextId: ContextId("dev"),
            selectedAtRFC3339: "2024-06-01T00:00:00Z",
            selectedBy: .restored
        )

        try await withDependencies {
            $0.contextRepository = fake
        } operation: {
            @Dependency(\.contextRepository) var repo
            try await repo.saveLastActiveContext(active)
            let loaded = try await repo.loadLastActiveContext()
            XCTAssertEqual(loaded?.contextId, ContextId("dev"))
        }
    }
}

// MARK: - ActiveContextWatchPort DI tests

final class ActiveContextWatchPortDITests: XCTestCase {
    func test_portCanBeOverridden_viaDependencies_emitsSingleEvent() async throws {
        let event = ActiveContextChanged(
            previous: nil,
            next: ActiveContext(contextId: ContextId("first"), selectedBy: .user)
        )
        let fake = FakeActiveContextWatchPort(events: [event])

        try await withDependencies {
            $0.activeContextWatch = fake
        } operation: {
            @Dependency(\.activeContextWatch) var watch
            var collected: [ActiveContextChanged] = []
            for try await e in watch.watchActiveContextChanges() {
                collected.append(e)
            }
            XCTAssertEqual(collected.count, 1)
            XCTAssertEqual(collected.first?.next.contextId, ContextId("first"))
        }
    }
}

// MARK: - SidebarReadModelPort DI tests

final class SidebarReadModelPortDITests: XCTestCase {
    func test_portCanBeOverridden_viaDependencies_currentSidebar() async throws {
        let pin = PinnedContext(
            contextId: ContextId("pinned-ctx"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 0
        )
        let sidebar = SidebarReadModel(pinned: [pin])
        let fake = FakeSidebarReadModelPort(sidebar: sidebar)

        try await withDependencies {
            $0.sidebarReadModel = fake
        } operation: {
            @Dependency(\.sidebarReadModel) var port
            let result = try await port.currentSidebar()
            XCTAssertEqual(result.pinned.count, 1)
            XCTAssertEqual(result.pinned.first?.contextId, ContextId("pinned-ctx"))
        }
    }
}

// MARK: - Test doubles

/// In-memory implementation of `ContextRepositoryPort` for tests.
private final class FakeContextRepository: ContextRepositoryPort, @unchecked Sendable {
    private var window = RecentContextWindow()
    private var pins: [ContextId: PinnedContext] = [:]
    private var lastActive: ActiveContext?

    func loadRecentWindow() async throws -> RecentContextWindow { window }

    func saveRecentWindow(_ w: RecentContextWindow) async throws { window = w }

    func loadPinnedContexts() async throws -> [PinnedContext] {
        pins.values.sorted { $0.displayOrder < $1.displayOrder }
    }

    func pin(_ context: PinnedContext) async throws { pins[context.contextId] = context }

    func unpin(contextId: ContextId) async throws { pins.removeValue(forKey: contextId) }

    func loadLastActiveContext() async throws -> ActiveContext? { lastActive }

    func saveLastActiveContext(_ context: ActiveContext) async throws { lastActive = context }
}

/// Replays a fixed sequence of `ActiveContextChanged` events then terminates.
private struct FakeActiveContextWatchPort: ActiveContextWatchPort {
    let events: [ActiveContextChanged]

    func watchActiveContextChanges() -> AsyncThrowingStream<ActiveContextChanged, Error> {
        let captured = events
        return AsyncThrowingStream { continuation in
            for event in captured { continuation.yield(event) }
            continuation.finish()
        }
    }
}

/// Returns a fixed `SidebarReadModel` for queries and watch.
private struct FakeSidebarReadModelPort: SidebarReadModelPort {
    let sidebar: SidebarReadModel

    func currentSidebar() async throws -> SidebarReadModel { sidebar }

    func watchSidebar() -> AsyncThrowingStream<SidebarReadModel, Error> {
        let captured = sidebar
        return AsyncThrowingStream { continuation in
            continuation.yield(captured)
            continuation.finish()
        }
    }
}

/// Deterministic clock that always returns a fixed RFC 3339 instant.
private struct FrozenClock: RFC3339Clock {
    let rfc3339: String

    func now() -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: rfc3339) ?? Date(timeIntervalSince1970: 0)
    }
}
