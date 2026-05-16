// KubeconfigContextRepositoryTests.swift — unit tests for KubeconfigContextRepository
// Coverage: recents window round-trip, pin/unpin lifecycle, context switching,
//           last-active-context persistence, sidebar projection, watch stream.

import XCTest
@testable import KubeconfigContextNavigationAdapter
import ContextNavigation
import ClusterConnectivity
import LocalPersistence
import SharedKernel

// MARK: - KubeconfigContextRepositoryTests

final class KubeconfigContextRepositoryExtendedTests: XCTestCase {

    // MARK: - Recents window

    func test_loadRecentWindow_defaultCap_whenNothingPersisted() async throws {
        let repo = makeRepo()
        let window = try await repo.loadRecentWindow()
        XCTAssertTrue(window.entries.isEmpty)
        XCTAssertEqual(window.maxEntries, 32)
    }

    func test_saveAndLoad_recentWindow_roundtrips() async throws {
        let repo = makeRepo()
        let entry = RecentContextEntry(
            contextId: ContextId("dev"),
            displayName: "Development",
            lastUsedRFC3339: "2024-06-01T00:00:00Z",
            useCount: 5
        )
        let window = RecentContextWindow(maxEntries: 16, entries: [entry])
        try await repo.saveRecentWindow(window)
        let loaded = try await repo.loadRecentWindow()
        XCTAssertEqual(loaded.maxEntries, 16)
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.contextId, ContextId("dev"))
        XCTAssertEqual(loaded.entries.first?.useCount, 5)
    }

    func test_saveRecentWindow_replacesExistingWindow() async throws {
        let repo = makeRepo()
        let first = RecentContextWindow(entries: [
            RecentContextEntry(
                contextId: ContextId("ctx-a"),
                displayName: "A",
                lastUsedRFC3339: "2024-01-01T00:00:00Z",
                useCount: 1
            )
        ])
        let second = RecentContextWindow(entries: [
            RecentContextEntry(
                contextId: ContextId("ctx-b"),
                displayName: "B",
                lastUsedRFC3339: "2024-02-01T00:00:00Z",
                useCount: 2
            )
        ])
        try await repo.saveRecentWindow(first)
        try await repo.saveRecentWindow(second)
        let loaded = try await repo.loadRecentWindow()
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.contextId, ContextId("ctx-b"))
    }

    // MARK: - Pin / unpin lifecycle

    func test_pin_addsEntry_loadReturnsIt() async throws {
        let repo = makeRepo()
        let pin = PinnedContext(
            contextId: ContextId("prod"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 0
        )
        try await repo.pin(pin)
        let pins = try await repo.loadPinnedContexts()
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(pins.first?.contextId, ContextId("prod"))
    }

    func test_pin_idempotent_doesNotDuplicate() async throws {
        let repo = makeRepo()
        let pin = PinnedContext(
            contextId: ContextId("staging"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 0
        )
        try await repo.pin(pin)
        try await repo.pin(pin)
        let pins = try await repo.loadPinnedContexts()
        XCTAssertEqual(pins.count, 1)
    }

    func test_unpin_removesEntry() async throws {
        let repo = makeRepo()
        let pin = PinnedContext(
            contextId: ContextId("qa"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 1
        )
        try await repo.pin(pin)
        try await repo.unpin(contextId: ContextId("qa"))
        let pins = try await repo.loadPinnedContexts()
        XCTAssertTrue(pins.isEmpty)
    }

    func test_unpin_noOp_whenNotPinned() async throws {
        let repo = makeRepo()
        try await repo.unpin(contextId: ContextId("never-pinned"))
        let pins = try await repo.loadPinnedContexts()
        XCTAssertTrue(pins.isEmpty)
    }

    func test_loadPinnedContexts_sortedByDisplayOrder() async throws {
        let repo = makeRepo()
        let pin1 = PinnedContext(
            contextId: ContextId("ctx-low"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 5
        )
        let pin0 = PinnedContext(
            contextId: ContextId("ctx-high"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 0
        )
        try await repo.pin(pin1)
        try await repo.pin(pin0)
        let pins = try await repo.loadPinnedContexts()
        XCTAssertEqual(pins.map(\.contextId), [ContextId("ctx-high"), ContextId("ctx-low")])
    }

    // MARK: - Last-active-context persistence

    func test_loadLastActiveContext_nilOnFirstLaunch() async throws {
        let repo = makeRepo()
        let loaded = try await repo.loadLastActiveContext()
        XCTAssertNil(loaded)
    }

    func test_saveAndLoad_lastActiveContext_roundtrips() async throws {
        let store = FakeClusterMetadataStore()
        let repo = makeRepo(metadataStore: store)
        let active = ActiveContext(
            contextId: ContextId("production"),
            selectedAtRFC3339: "2024-06-01T12:00:00Z",
            selectedBy: .user
        )
        try await repo.saveLastActiveContext(active)
        let loaded = try await repo.loadLastActiveContext()
        let ctx = try XCTUnwrap(loaded)
        XCTAssertEqual(ctx.contextId, ContextId("production"))
        XCTAssertEqual(ctx.selectedBy, .user)
        XCTAssertEqual(ctx.selectedAtRFC3339, "2024-06-01T12:00:00Z")
    }

    func test_saveLastActiveContext_overwritesPrevious() async throws {
        let store = FakeClusterMetadataStore()
        let repo = makeRepo(metadataStore: store)

        let first = ActiveContext(
            contextId: ContextId("ctx-first"),
            selectedAtRFC3339: "2024-01-01T00:00:00Z",
            selectedBy: .user
        )
        let second = ActiveContext(
            contextId: ContextId("ctx-second"),
            selectedAtRFC3339: "2024-02-01T00:00:00Z",
            selectedBy: .restored
        )
        try await repo.saveLastActiveContext(first)
        try await repo.saveLastActiveContext(second)

        let loaded = try await repo.loadLastActiveContext()
        XCTAssertEqual(loaded?.contextId, ContextId("ctx-second"))
        XCTAssertEqual(loaded?.selectedBy, .restored)
    }

    // MARK: - Helpers

    private func makeRepo(
        loader: any KubeconfigLoaderPort = StubKubeconfigLoader(),
        metadataStore: any ClusterMetadataStorePort = FakeClusterMetadataStore()
    ) -> KubeconfigContextRepository {
        KubeconfigContextRepository(loader: loader, metadataStore: metadataStore)
    }
}

// MARK: - KubeconfigActiveContextWatchTests

final class KubeconfigActiveContextWatchExtendedTests: XCTestCase {

    func test_watchEmitsInitial_withPersistedOverride() async throws {
        let store = FakeClusterMetadataStore()
        let persisted = ActiveContext(
            contextId: ContextId("restored-ctx"),
            selectedAtRFC3339: "2024-01-01T00:00:00Z",
            selectedBy: .restored
        )
        let repo = KubeconfigContextRepository(
            loader: StubKubeconfigLoader(),
            metadataStore: store
        )
        try await repo.saveLastActiveContext(persisted)

        let watch = KubeconfigActiveContextWatch(repository: repo, loader: StubKubeconfigLoader())
        let stream = watch.watchActiveContextChanges()
        var events: [ActiveContextChanged] = []
        for try await event in stream {
            events.append(event)
            break
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.next.contextId, ContextId("restored-ctx"))
        XCTAssertEqual(events.first?.next.selectedBy, .restored)
    }

    func test_watchFallsBack_toKubeconfig_whenNoPersistedOverride() async throws {
        let loader = StubKubeconfigLoader(currentContext: "kind-local")
        let repo = KubeconfigContextRepository(
            loader: loader,
            metadataStore: FakeClusterMetadataStore()
        )
        let watch = KubeconfigActiveContextWatch(repository: repo, loader: loader)

        let stream = watch.watchActiveContextChanges()
        var events: [ActiveContextChanged] = []
        for try await event in stream {
            events.append(event)
            break
        }
        XCTAssertEqual(events.first?.next.contextId, ContextId("kind-local"))
        XCTAssertEqual(events.first?.next.selectedBy, .fallback)
    }

    func test_select_emitsChangeEvent() async throws {
        let repo = KubeconfigContextRepository(
            loader: StubKubeconfigLoader(),
            metadataStore: FakeClusterMetadataStore()
        )
        let watch = KubeconfigActiveContextWatch(repository: repo, loader: StubKubeconfigLoader())
        let stream = watch.watchActiveContextChanges()

        let collectTask: Task<[ActiveContextChanged], Error> = Task {
            var collected: [ActiveContextChanged] = []
            for try await event in stream {
                collected.append(event)
                if collected.count == 2 { break }
            }
            return collected
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        await watch.select(contextId: ContextId("selected-ctx"), origin: .user)

        let events = try await collectTask.value
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last?.next.contextId, ContextId("selected-ctx"))
        XCTAssertEqual(events.last?.next.selectedBy, .user)
    }

    func test_select_sameContext_noEvent() async throws {
        let loader = StubKubeconfigLoader(currentContext: "same-ctx")
        let repo = KubeconfigContextRepository(
            loader: loader,
            metadataStore: FakeClusterMetadataStore()
        )
        let watch = KubeconfigActiveContextWatch(repository: repo, loader: loader)
        let stream = watch.watchActiveContextChanges()

        let collectTask: Task<[ActiveContextChanged], Error> = Task {
            var collected: [ActiveContextChanged] = []
            for try await event in stream {
                collected.append(event)
                if collected.count >= 2 { break }
            }
            return collected
        }

        // wait for initial event
        try await Task.sleep(nanoseconds: 50_000_000)
        // selecting the same context should produce no additional event
        await watch.select(contextId: ContextId("same-ctx"), origin: .user)
        try await Task.sleep(nanoseconds: 100_000_000)

        collectTask.cancel()
        let events = (try? await collectTask.value) ?? []
        // Only the initial event should have arrived (the same-context select is a no-op).
        XCTAssertEqual(events.count, 1)
    }
}

// MARK: - KubeconfigSidebarReadModelTests

final class KubeconfigSidebarReadModelExtendedTests: XCTestCase {

    func test_currentSidebar_empty_whenNoData() async throws {
        let (repo, watch) = makeComponents()
        let sidebar = KubeconfigSidebarReadModel(repository: repo, watch: watch)
        let result = try await sidebar.currentSidebar()
        XCTAssertTrue(result.pinned.isEmpty)
        XCTAssertTrue(result.recents.isEmpty)
    }

    func test_currentSidebar_excludesPinned_fromRecents() async throws {
        let (repo, watch) = makeComponents()
        let pin = PinnedContext(
            contextId: ContextId("prod"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 0
        )
        try await repo.pin(pin)
        let entry = RecentContextEntry(
            contextId: ContextId("prod"),
            displayName: "Production",
            lastUsedRFC3339: "2024-06-01T00:00:00Z",
            useCount: 10,
            pinned: true
        )
        try await repo.saveRecentWindow(RecentContextWindow(entries: [entry]))

        let sidebar = KubeconfigSidebarReadModel(repository: repo, watch: watch)
        let result = try await sidebar.currentSidebar()
        XCTAssertEqual(result.pinned.count, 1)
        XCTAssertTrue(result.recents.isEmpty, "Pinned entry must not be duplicated in recents")
    }

    func test_currentSidebar_recents_onlyNonPinned() async throws {
        let (repo, watch) = makeComponents()
        let pin = PinnedContext(
            contextId: ContextId("pinned"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 0
        )
        try await repo.pin(pin)
        let entries = [
            RecentContextEntry(
                contextId: ContextId("pinned"),
                displayName: "Pinned",
                lastUsedRFC3339: "2024-06-01T00:00:00Z",
                useCount: 5
            ),
            RecentContextEntry(
                contextId: ContextId("recent"),
                displayName: "Recent",
                lastUsedRFC3339: "2024-05-01T00:00:00Z",
                useCount: 2
            ),
        ]
        try await repo.saveRecentWindow(RecentContextWindow(entries: entries))

        let sidebar = KubeconfigSidebarReadModel(repository: repo, watch: watch)
        let result = try await sidebar.currentSidebar()
        XCTAssertEqual(result.pinned.count, 1)
        XCTAssertEqual(result.recents.count, 1)
        XCTAssertEqual(result.recents.first?.contextId, ContextId("recent"))
    }

    // MARK: - Helpers

    private func makeComponents(
        loader: any KubeconfigLoaderPort = StubKubeconfigLoader()
    ) -> (KubeconfigContextRepository, KubeconfigActiveContextWatch) {
        let repo = KubeconfigContextRepository(
            loader: loader,
            metadataStore: FakeClusterMetadataStore()
        )
        let watch = KubeconfigActiveContextWatch(repository: repo, loader: loader)
        return (repo, watch)
    }
}

// MARK: - Test doubles

/// Stub that returns a minimal in-memory kubeconfig without touching disk.
private struct StubKubeconfigLoader: KubeconfigLoaderPort {
    let currentContext: String?

    init(currentContext: String? = nil) {
        self.currentContext = currentContext
    }

    func load(from path: KubeconfigPath) async throws -> Kubeconfig {
        let contexts: [KubeconfigContext] = currentContext.map {
            [KubeconfigContext(name: $0, cluster: $0, user: $0)]
        } ?? []
        return Kubeconfig(
            sourcePath: path,
            sourceMTimeRFC3339: "2024-01-01T00:00:00Z",
            currentContext: currentContext,
            contexts: contexts
        )
    }

    func contexts(in config: Kubeconfig) -> [KubeconfigContext] { config.contexts }

    func activeContext(in config: Kubeconfig) -> KubeconfigContext? {
        guard let current = config.currentContext else { return nil }
        return config.contexts.first { $0.name == current }
    }
}

/// Fake in-memory `ClusterMetadataStorePort` backed by a thread-safe dictionary.
private final class FakeClusterMetadataStore: ClusterMetadataStorePort, @unchecked Sendable {
    private var store: [String: ClusterAnalysisCache] = [:]
    private let lock = NSLock()

    private func storeKey(clusterId: UUID, kind: AnalysisKind) -> String {
        "\(clusterId.uuidString)-\(kind.rawValue)"
    }

    func cachedAnalysis(
        clusterId: UUID,
        kind: AnalysisKind,
        now: Date
    ) async throws -> ClusterAnalysisCache? {
        lock.withLock { store[storeKey(clusterId: clusterId, kind: kind)] }
    }

    func upsertAnalysis(_ entry: ClusterAnalysisCache) async throws {
        lock.withLock { store[storeKey(clusterId: entry.clusterId, kind: entry.kind)] = entry }
    }

    @discardableResult
    func pruneExpired(now: Date) async throws -> Int { 0 }
}
