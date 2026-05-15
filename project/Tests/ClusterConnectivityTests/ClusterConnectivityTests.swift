// ClusterConnectivityTests.swift — cluster_connectivity bounded context
// XCTest coverage: domain types, actor lifecycle, DI port overrides.

import XCTest
import Dependencies
@testable import ClusterConnectivity
import SharedKernel

// MARK: - ClusterDomainTests

final class ClusterDomainTests: XCTestCase {
    func test_cluster_construction_roundtrips_fields() {
        let id = ClusterId("test-cluster-id")
        let cluster = Cluster(
            id: id,
            name: "kind-local",
            server: "https://127.0.0.1:6443",
            caStrategy: .system,
            insecureSkipTLSVerify: false
        )

        XCTAssertEqual(cluster.id, id)
        XCTAssertEqual(cluster.name, "kind-local")
        XCTAssertEqual(cluster.server, "https://127.0.0.1:6443")
        XCTAssertEqual(cluster.caStrategy, .system)
        XCTAssertFalse(cluster.insecureSkipTLSVerify)
    }

    func test_cluster_embedded_ca_strategy() {
        let pem = "-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----"
        let cluster = Cluster(
            id: ClusterId("x"),
            name: "gke",
            server: "https://34.0.0.1",
            caStrategy: .embedded(pemData: pem),
            insecureSkipTLSVerify: false
        )

        if case .embedded(let data) = cluster.caStrategy {
            XCTAssertEqual(data, pem)
        } else {
            XCTFail("Expected .embedded caStrategy")
        }
    }

    func test_cluster_codable_roundtrip() throws {
        let cluster = Cluster(
            id: ClusterId("abc-123"),
            name: "prod",
            server: "https://k8s.example.com",
            caStrategy: .referenced(path: "/etc/ssl/ca.pem"),
            insecureSkipTLSVerify: false
        )

        let data = try JSONEncoder().encode(cluster)
        let decoded = try JSONDecoder().decode(Cluster.self, from: data)

        XCTAssertEqual(cluster, decoded)
    }
}

// MARK: - KubeconfigDomainTests

final class KubeconfigDomainTests: XCTestCase {
    func test_kubeconfig_empty_collections() {
        let cfg = Kubeconfig(
            sourcePath: KubeconfigPath("/home/user/.kube/config"),
            sourceMTimeRFC3339: "2024-01-01T00:00:00Z"
        )

        XCTAssertTrue(cfg.clusters.isEmpty)
        XCTAssertTrue(cfg.users.isEmpty)
        XCTAssertTrue(cfg.contexts.isEmpty)
        XCTAssertNil(cfg.currentContext)
    }

    func test_kubeconfig_context_namespace_defaults_to_default() {
        let ctx = KubeconfigContext(
            name: "my-ctx",
            cluster: "my-cluster",
            user: "my-user"
        )
        XCTAssertEqual(ctx.namespace, "default")
    }

    func test_kubeconfig_cluster_insecure_defaults_to_false() {
        let entry = KubeconfigCluster(name: "local", server: "https://localhost")
        XCTAssertFalse(entry.insecureSkipTLSVerify)
    }
}

// MARK: - HealthStatusTests

final class HealthStatusTests: XCTestCase {
    func test_health_status_all_states_round_trip() throws {
        for state in HealthState.allCases {
            let status = HealthStatus(
                clusterId: ClusterId("c"),
                probedAt: "2024-01-01T00:00:00Z",
                state: state
            )
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(HealthStatus.self, from: data)
            XCTAssertEqual(decoded.state, state, "Round-trip failed for \(state)")
        }
    }
}

// MARK: - ClusterSessionActorTests

final class ClusterSessionActorTests: XCTestCase {
    func test_initialState_isDisconnected() async {
        let actor = ClusterSessionActor(clusterId: ClusterId("test"))
        let state = await actor.state
        XCTAssertEqual(state, .disconnected)
    }

    func test_transition_to_connecting() async {
        let actor = ClusterSessionActor(clusterId: ClusterId("test"))
        await actor.transition(to: .connecting)
        let state = await actor.state
        XCTAssertEqual(state, .connecting)
    }

    func test_transition_to_connected_with_version() async {
        let actor = ClusterSessionActor(clusterId: ClusterId("test"))
        await actor.transition(to: .connected(serverVersion: "v1.29.3"))
        let state = await actor.state
        XCTAssertEqual(state, .connected(serverVersion: "v1.29.3"))
    }

    func test_transition_to_degraded() async {
        let actor = ClusterSessionActor(clusterId: ClusterId("test"))
        await actor.transition(to: .degraded(reason: "exec-plugin-failed"))
        let state = await actor.state
        XCTAssertEqual(state, .degraded(reason: "exec-plugin-failed"))
    }

    func test_transition_to_terminating() async {
        let actor = ClusterSessionActor(clusterId: ClusterId("test"))
        await actor.transition(to: .terminating)
        let state = await actor.state
        XCTAssertEqual(state, .terminating)
    }

    func test_watchStream_register_and_deregister() async {
        let actor = ClusterSessionActor(clusterId: ClusterId("test"))
        let ref = WatchStreamRef(
            id: UUID(),
            apiGroup: "apps",
            resourceKind: "Deployment",
            namespace: "default",
            openedAt: "2024-01-01T00:00:00Z",
            status: .active
        )

        await actor.registerWatchStream(ref)
        let before = await actor.currentWatchStreamRegistry()
        XCTAssertEqual(before.count, 1)

        await actor.deregisterWatchStream(id: ref.id)
        let after = await actor.currentWatchStreamRegistry()
        XCTAssertTrue(after.isEmpty)
    }

    func test_poolStats_update() async {
        let actor = ClusterSessionActor(clusterId: ClusterId("test"))
        let stats = PoolStats(
            idleConnections: 3,
            activeConnections: 1,
            requestsInFlight: 2,
            requestsCompleted: 100,
            requestsFailed: 5
        )

        await actor.updatePoolStats(stats)
        let current = await actor.currentPoolStats()
        XCTAssertEqual(current, stats)
    }
}

// MARK: - KubeconfigLoaderPortDITests

final class KubeconfigLoaderPortDITests: XCTestCase {
    func test_portCanBeOverridden_viaDependencies() async throws {
        let fake = FakeKubeconfigLoader(returning: Kubeconfig(
            sourcePath: KubeconfigPath("/dev/null"),
            sourceMTimeRFC3339: "2024-01-01T00:00:00Z"
        ))

        try await withDependencies {
            $0.kubeconfigLoader = fake
        } operation: {
            @Dependency(\.kubeconfigLoader) var loader
            let cfg = try await loader.load(from: KubeconfigPath("/dev/null"))
            XCTAssertTrue(cfg.contexts.isEmpty)
        }
    }

    func test_activeContext_returnsNil_whenCurrentContextIsNil() async throws {
        let cfg = Kubeconfig(
            sourcePath: KubeconfigPath("/etc/kube/config"),
            sourceMTimeRFC3339: "2024-01-01T00:00:00Z",
            currentContext: nil,
            contexts: [KubeconfigContext(name: "prod", cluster: "prod", user: "admin")]
        )
        let loader = UnimplementedKubeconfigLoaderPort()
        let active = loader.activeContext(in: cfg)
        XCTAssertNil(active)
    }

    func test_activeContext_returnsMatchingContext() async throws {
        let target = KubeconfigContext(name: "staging", cluster: "stg", user: "dev")
        let cfg = Kubeconfig(
            sourcePath: KubeconfigPath("/etc/kube/config"),
            sourceMTimeRFC3339: "2024-01-01T00:00:00Z",
            currentContext: "staging",
            contexts: [
                KubeconfigContext(name: "prod", cluster: "prod", user: "admin"),
                target,
            ]
        )
        let loader = UnimplementedKubeconfigLoaderPort()
        let active = loader.activeContext(in: cfg)
        XCTAssertEqual(active, target)
    }
}

// MARK: - Test doubles

private struct FakeKubeconfigLoader: KubeconfigLoaderPort {
    let returning: Kubeconfig

    func load(from path: KubeconfigPath) async throws -> Kubeconfig {
        returning
    }

    func contexts(in config: Kubeconfig) -> [KubeconfigContext] {
        config.contexts
    }

    func activeContext(in config: Kubeconfig) -> KubeconfigContext? {
        guard let current = config.currentContext else { return nil }
        return config.contexts.first { $0.name == current }
    }
}
