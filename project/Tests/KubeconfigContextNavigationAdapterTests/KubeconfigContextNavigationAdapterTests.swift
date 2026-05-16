// KubeconfigContextNavigationAdapterTests.swift
// XCTest coverage for KubeconfigContextNavigationAdapter:
//   - KubeconfigContextRepository (repo + persistence bridge)
//   - KubeconfigActiveContextWatch (initial resolution + stream emission)
//   - KubeconfigSidebarReadModel (projection)

import XCTest
@testable import KubeconfigContextNavigationAdapter
import ContextNavigation
import ClusterConnectivity
import LocalPersistence
import SharedKernel

// MARK: - Repository tests

final class KubeconfigContextRepositoryTests: XCTestCase {

    func test_loadRecentWindow_returnsDefaultWindowWhenEmpty() async throws {
        let repo = makeRepo()
        let window = try await repo.loadRecentWindow()
        XCTAssertTrue(window.entries.isEmpty)
        XCTAssertEqual(window.maxEntries, 32)
    }

    func test_saveAndLoadPinnedContexts_roundtrip() async throws {
        let repo = makeRepo()
        let pin = PinnedContext(
            contextId: ContextId("prod"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 0
        )
        try await repo.pin(pin)
        let loaded = try await repo.loadPinnedContexts()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.contextId, ContextId("prod"))
    }

    func test_unpin_removesEntry() async throws {
        let repo = makeRepo()
        let pin = PinnedContext(
            contextId: ContextId("staging"),
            pinnedAtRFC3339: "2024-01-01T00:00:00Z",
            displayOrder: 1
        )
        try await repo.pin(pin)
        try await repo.unpin(contextId: ContextId("staging"))
        let loaded = try await repo.loadPinnedContexts()
        XCTAssertTrue(loaded.isEmpty)
    }

    func test_loadLastActiveContext_nilOnFirstLaunch() async throws {
        let repo = makeRepo()
        let loaded = try await repo.loadLastActiveContext()
        XCTAssertNil(loaded)
    }

    func test_saveAndLoadLastActiveContext_persistsViaMetadataStore() async throws {
        let store = FakeClusterMetadataStore()
        let repo = makeRepo(metadataStore: store)
        let active = ActiveContext(
            contextId: ContextId("dev"),
            selectedAtRFC3339: "2024-06-01T00:00:00Z",
            selectedBy: .user
        )
        try await repo.saveLastActiveContext(active)
        let loaded = try await repo.loadLastActiveContext()
        XCTAssertEqual(loaded?.contextId, ContextId("dev"))
        XCTAssertEqual(loaded?.selectedBy, .user)
    }

    // MARK: Helpers

    private func makeRepo(
        loader: any KubeconfigLoaderPort = FakeKubeconfigLoader(),
        metadataStore: any ClusterMetadataStorePort = FakeClusterMetadataStore()
    ) -> KubeconfigContextRepository {
        KubeconfigContextRepository(loader: loader, metadataStore: metadataStore)
    }
}

// MARK: - Active context watch tests

final class KubeconfigActiveContextWatchTests: XCTestCase {

    func test_watchEmitsInitialEvent_withPersistedOverride() async throws {
        let store = FakeClusterMetadataStore()
        let persisted = ActiveContext(
            contextId: ContextId("restored-ctx"),
            selectedAtRFC3339: "2024-01-01T00:00:00Z",
            selectedBy: .restored
        )
        let repo = KubeconfigContextRepository(loader: FakeKubeconfigLoader(), metadataStore: store)
        try await repo.saveLastActiveContext(persisted)

        let watch = KubeconfigActiveContextWatch(repository: repo, loader: FakeKubeconfigLoader())
        var events: [ActiveContextChanged] = []
        let stream = watch.watchActiveContextChanges()
        for try await event in stream {
            events.append(event)
            break // collect only the initial event
        }
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.next.contextId, ContextId("restored-ctx"))
        XCTAssertEqual(events.first?.next.selectedBy, .restored)
    }

    func test_watchFallsBackToKubeconfig_whenNoPersistedOverride() async throws {
        let loader = FakeKubeconfigLoader(currentContext: "kind-local")
        let repo = KubeconfigContextRepository(loader: loader, metadataStore: FakeClusterMetadataStore())
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

    func test_selectContext_emitsChangeEvent() async throws {
        let repo = KubeconfigContextRepository(
            loader: FakeKubeconfigLoader(),
            metadataStore: FakeClusterMetadataStore()
        )
        let watch = KubeconfigActiveContextWatch(repository: repo, loader: FakeKubeconfigLoader())

        let stream = watch.watchActiveContextChanges()
        var task: Task<[ActiveContextChanged], Error>?
        task = Task {
            var collected: [ActiveContextChanged] = []
            for try await event in stream {
                collected.append(event)
                if collected.count == 2 { break }
            }
            return collected
        }

        // allow stream to start and emit initial
        try await Task.sleep(nanoseconds: 50_000_000)
        await watch.select(contextId: ContextId("new-ctx"), origin: .user)

        let events = try await task!.value
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.last?.next.contextId, ContextId("new-ctx"))
        XCTAssertEqual(events.last?.next.selectedBy, .user)
    }
}

// MARK: - Sidebar read model tests

final class KubeconfigSidebarReadModelTests: XCTestCase {

    func test_currentSidebar_returnsEmptySidebarWhenNoData() async throws {
        let repo = KubeconfigContextRepository(
            loader: FakeKubeconfigLoader(),
            metadataStore: FakeClusterMetadataStore()
        )
        let watch = KubeconfigActiveContextWatch(repository: repo, loader: FakeKubeconfigLoader())
        let sidebar = KubeconfigSidebarReadModel(repository: repo, watch: watch)

        let result = try await sidebar.currentSidebar()
        XCTAssertTrue(result.pinned.isEmpty)
        XCTAssertTrue(result.recents.isEmpty)
    }

    func test_currentSidebar_excludesPinnedFromRecents() async throws {
        let repo = KubeconfigContextRepository(
            loader: FakeKubeconfigLoader(),
            metadataStore: FakeClusterMetadataStore()
        )
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
            useCount: 3,
            pinned: true
        )
        try await repo.saveRecentWindow(RecentContextWindow(entries: [entry]))

        let watch = KubeconfigActiveContextWatch(repository: repo, loader: FakeKubeconfigLoader())
        let sidebar = KubeconfigSidebarReadModel(repository: repo, watch: watch)

        let result = try await sidebar.currentSidebar()
        XCTAssertEqual(result.pinned.count, 1)
        XCTAssertTrue(result.recents.isEmpty, "Pinned entry must not appear in recents")
    }
}

// MARK: - Test doubles

/// Fake kubeconfig loader returning a minimal in-memory kubeconfig.
private struct FakeKubeconfigLoader: KubeconfigLoaderPort {
    let currentContext: String?

    init(currentContext: String? = nil) {
        self.currentContext = currentContext
    }

    func load(from path: KubeconfigPath) async throws -> Kubeconfig {
        var ctxList: [KubeconfigContext] = []
        if let name = currentContext {
            ctxList = [KubeconfigContext(name: name, cluster: name, user: name)]
        }
        return Kubeconfig(
            sourcePath: path,
            sourceMTimeRFC3339: "2024-01-01T00:00:00Z",
            currentContext: currentContext,
            contexts: ctxList
        )
    }

    func contexts(in config: Kubeconfig) -> [KubeconfigContext] { config.contexts }

    func activeContext(in config: Kubeconfig) -> KubeconfigContext? {
        guard let current = config.currentContext else { return nil }
        return config.contexts.first { $0.name == current }
    }
}

/// Fake in-memory `ClusterMetadataStorePort` — stores a single analysis entry per key.
private final class FakeClusterMetadataStore: ClusterMetadataStorePort, @unchecked Sendable {
    private var store: [String: ClusterAnalysisCache] = [:]
    private let lock = NSLock()

    private func key(clusterId: UUID, kind: AnalysisKind) -> String {
        "\(clusterId)-\(kind.rawValue)"
    }

    func cachedAnalysis(
        clusterId: UUID,
        kind: AnalysisKind,
        now: Date
    ) async throws -> ClusterAnalysisCache? {
        lock.withLock { store[key(clusterId: clusterId, kind: kind)] }
    }

    func upsertAnalysis(_ entry: ClusterAnalysisCache) async throws {
        lock.withLock { store[key(clusterId: entry.clusterId, kind: entry.kind)] = entry }
    }

    @discardableResult
    func pruneExpired(now: Date) async throws -> Int { 0 }
}
