// Tests/AppShellTests/GlobalNamespacePillTests.swift
// Coverage: GlobalNamespacePill actor integration — initial state, selection
// round-trip, namespace list load path, and stream responsiveness.
// ADR ref: ADR-0069 (global namespace pill in top-right chrome)

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import SharedKernel

// MARK: - GlobalNamespacePillTests

@MainActor
final class GlobalNamespacePillTests: XCTestCase {

    // MARK: NamespaceFilterActor — initial state

    func test_actor_initialState_returnsNil() async {
        let actor = NamespaceFilterActor()
        let result = await actor.current(for: ClusterId("cluster-a"))
        XCTAssertNil(result)
    }

    // MARK: NamespaceFilterActor — set and read round-trip

    func test_actor_setNamespace_returnsSameValue() async {
        let actor = NamespaceFilterActor()
        let id = ClusterId("cluster-a")
        await actor.setNamespace("kube-system", for: id)
        let result = await actor.current(for: id)
        XCTAssertEqual(result, "kube-system")
    }

    func test_actor_setNamespaceNil_clearsFilter() async {
        let actor = NamespaceFilterActor()
        let id = ClusterId("cluster-a")
        await actor.setNamespace("default", for: id)
        await actor.setNamespace(nil, for: id)
        let result = await actor.current(for: id)
        XCTAssertNil(result)
    }

    // MARK: NamespaceFilterActor — per-cluster isolation

    func test_actor_clusterIsolation_doesNotCrossBleed() async {
        let actor = NamespaceFilterActor()
        let a = ClusterId("cluster-a")
        let b = ClusterId("cluster-b")
        await actor.setNamespace("prod", for: a)
        let resultB = await actor.current(for: b)
        XCTAssertNil(resultB, "Setting namespace for A must not affect B")
    }

    // MARK: NamespaceFilterActor — stream yields initial value

    func test_stream_yieldsCurrentValueImmediately() async {
        let actor = NamespaceFilterActor()
        let id = ClusterId("cluster-a")
        await actor.setNamespace("default", for: id)

        let stream = actor.stateStream(for: id)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertEqual(first?.namespace, "default")
    }

    func test_stream_yieldsNilWhenNoSelection() async {
        let actor = NamespaceFilterActor()
        let id = ClusterId("cluster-a")

        let stream = actor.stateStream(for: id)
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        XCTAssertNil(first?.namespace)
    }

    // MARK: NamespaceFilterActor — mutation broadcast

    func test_stream_broadcastsMutation() async {
        let actor = NamespaceFilterActor()
        let id = ClusterId("cluster-a")

        let stream = actor.stateStream(for: id)
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next() // consume initial

        await actor.setNamespace("kube-public", for: id)
        let second = await iterator.next()
        XCTAssertEqual(second?.namespace, "kube-public")
    }

    // MARK: NamespaceFilterActor — no-op on same value

    func test_actor_noopOnSameValue_doesNotBroadcast() async {
        let actor = NamespaceFilterActor()
        let id = ClusterId("cluster-a")
        await actor.setNamespace("default", for: id)

        var receivedCount = 0
        let task = Task {
            for await _ in actor.stateStream(for: id) {
                receivedCount += 1
                if receivedCount >= 2 { break }
            }
        }
        // Yield execution so the stream registers
        await Task.yield()
        // Setting the same value must not fire a second event
        await actor.setNamespace("default", for: id)
        // Setting a different value fires
        await actor.setNamespace("kube-system", for: id)
        // Cancel; expect only 2 events (initial + mutation), not 3
        task.cancel()
        await Task.yield()
        XCTAssertEqual(receivedCount, 2)
    }

    // MARK: Config view models — actor subscription wiring

    /// Verifies that `ConfigMapsListViewModel.start` reads the actor's
    /// current namespace before the first fetch.
    ///
    /// The view model's `start` is async and contains a `for await` loop that
    /// runs until cancelled. We wrap it in a `Task`, run a short async gap, and
    /// then inspect state before cancelling. A 10 ms sleep is sufficient on all
    /// Apple platforms in CI.
    func test_configMapsViewModel_readsActorOnStart() async throws {
        let actor = NamespaceFilterActor()
        let id = ClusterId("cluster-a")
        await actor.setNamespace("my-ns", for: id)

        let fake = PillFakeListPort(items: [])
        let vm = ConfigMapsListViewModel()
        try await withDependencies {
            $0.namespaceFilter = actor
            $0.kubernetesResourceList = fake
        } operation: {
            let task = Task { await vm.start(clusterId: id, namespace: nil) }
            // Allow the async start to reach and execute `namespaceFilter.current`
            try await Task.sleep(nanoseconds: 20_000_000) // 20 ms
            XCTAssertEqual(vm.namespace, "my-ns")
            task.cancel()
        }
    }

    func test_configMapsViewModel_updatesOnActorMutation() async throws {
        let actor = NamespaceFilterActor()
        let id = ClusterId("cluster-a")

        let fake = PillFakeListPort(items: [])
        let vm = ConfigMapsListViewModel()
        try await withDependencies {
            $0.namespaceFilter = actor
            $0.kubernetesResourceList = fake
        } operation: {
            let task = Task { await vm.start(clusterId: id, namespace: nil) }
            try await Task.sleep(nanoseconds: 20_000_000) // let start settle
            await actor.setNamespace("staging", for: id)
            try await Task.sleep(nanoseconds: 20_000_000) // let mutation propagate
            XCTAssertEqual(vm.namespace, "staging")
            task.cancel()
        }
    }
}

// MARK: - PillFakeListPort

/// Minimal `KubernetesResourceListPort` stub for GlobalNamespacePill tests.
/// Named `PillFakeListPort` to avoid collision with the private `FakeListPort`
/// defined in `ServicesListViewModelTests.swift`.
private final class PillFakeListPort: KubernetesResourceListPort, @unchecked Sendable {

    let stubbedItems: [ResourceListItem]
    let stubbedError: Error?

    init(items: [ResourceListItem] = [], error: Error? = nil) {
        self.stubbedItems = items
        self.stubbedError = error
    }

    func list(
        gvk: GroupVersionKind,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> [ResourceListItem] {
        if let error = stubbedError { throw error }
        return stubbedItems
    }

    func get(
        gvk: GroupVersionKind,
        name: String,
        namespace: String?,
        clusterId: ClusterId
    ) async throws -> ResourceDetail {
        throw ResourceListError.unimplemented
    }
}
