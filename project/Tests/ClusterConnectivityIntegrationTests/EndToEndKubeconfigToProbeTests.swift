// EndToEndKubeconfigToProbeTests.swift — ClusterConnectivityIntegrationTests
// Exercises the full cluster_connectivity vertical slice end-to-end:
//   YamsKubeconfigLoader → ClusterParams resolver → SwiftkubeApiAdapter.probeHealth
// No real Kubernetes cluster required; the probe target is https://127.0.0.1:1
// (always connection-refused), so the expected outcome is HealthState.unreachable.

import XCTest
import Foundation
import ClusterConnectivity
import SharedKernel
@testable import YamsKubeconfigAdapter
@testable import SwiftkubeClientAdapter

// MARK: - EndToEndKubeconfigToProbeTests

final class EndToEndKubeconfigToProbeTests: XCTestCase {

    // MARK: - Happy-path: load → resolve → probe → unreachable

    /// Writes a synthetic kubeconfig, loads it via `YamsKubeconfigLoader`,
    /// builds a `SwiftkubeApiAdapter` whose resolver mirrors the composition-root
    /// wiring in `K8sManagerApp.swift`, calls `probeHealth`, and asserts that the
    /// result is `.unreachable` (not a thrown error) because `https://127.0.0.1:1`
    /// always refuses connections.
    func test_endToEnd_loadKubeconfig_probeHealth_unreachableServer() async throws {
        // 1 — Write synthetic kubeconfig to a temp file.
        let yaml = """
        apiVersion: v1
        kind: Config
        current-context: test-context
        clusters:
          - name: test-cluster
            cluster:
              server: https://127.0.0.1:1
              insecure-skip-tls-verify: true
        users:
          - name: test-user
            user:
              token: test-token
        contexts:
          - name: test-context
            context:
              cluster: test-cluster
              user: test-user
              namespace: default
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("k8smgr-integration-\(UUID().uuidString).yaml")
        guard let yamlData = yaml.data(using: .utf8) else {
            XCTFail("Failed to encode YAML as UTF-8")
            return
        }
        try yamlData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // 2 — Load via the live Yams adapter (no mock).
        let loader = YamsKubeconfigLoader()
        let kubeconfig = try await loader.load(from: KubeconfigPath(tempURL.path))

        XCTAssertEqual(kubeconfig.contexts.count, 1, "Expected exactly one context")
        XCTAssertEqual(kubeconfig.currentContext, "test-context")
        XCTAssertEqual(kubeconfig.clusters.count, 1)
        XCTAssertEqual(kubeconfig.users.count, 1)

        // 3 — Build a resolver that mirrors K8sManagerApp.buildResolver / mapToClusterParams.
        //     ClusterId("test-cluster") matches context.cluster == "test-cluster".
        let resolver: SwiftkubeApiAdapter.ClusterResolver = { clusterId in
            guard let context = kubeconfig.contexts.first(where: { $0.cluster == clusterId.rawValue })
                    ?? kubeconfig.contexts.first(where: { $0.name == clusterId.rawValue }) else {
                throw KubernetesApiError.transportError(
                    detail: "ClusterId '\(clusterId.rawValue)' not found in test kubeconfig"
                )
            }
            guard let kubeconfigCluster = kubeconfig.clusters.first(where: { $0.name == context.cluster }) else {
                throw KubernetesApiError.transportError(
                    detail: "Cluster '\(context.cluster)' not found in test kubeconfig"
                )
            }
            guard let kubeconfigUser = kubeconfig.users.first(where: { $0.name == context.user }) else {
                throw KubernetesApiError.transportError(
                    detail: "User '\(context.user)' not found in test kubeconfig"
                )
            }
            guard let serverURL = URL(string: kubeconfigCluster.server) else {
                throw KubernetesApiError.transportError(
                    detail: "Invalid server URL: '\(kubeconfigCluster.server)'"
                )
            }
            return ClusterParams(
                server: serverURL,
                auth: .bearerToken(BearerTokenAuth(token: kubeconfigUser.token ?? "")),
                insecureSkipTLSVerify: kubeconfigCluster.insecureSkipTLSVerify,
                caStrategy: .system
            )
        }

        // 4 — Construct the adapter with the resolver above.
        let adapter = SwiftkubeApiAdapter(resolver: resolver)

        // 5 — Probe the unreachable server.
        //     Connection to https://127.0.0.1:1 is immediately refused; the adapter
        //     MUST surface this as HealthStatus.state == .unreachable (not throw).
        let health = try await adapter.probeHealth(clusterId: ClusterId("test-cluster"))

        XCTAssertEqual(
            health.state, .unreachable,
            "Expected .unreachable for a refused connection, got \(health.state)"
        )
        XCTAssertEqual(
            health.clusterId, ClusterId("test-cluster"),
            "ClusterId must round-trip through the adapter"
        )
        XCTAssertFalse(
            health.probedAt.isEmpty,
            "probedAt RFC 3339 timestamp must be present"
        )
    }

    // MARK: - Resolver KubernetesApiError propagates (not wrapped in HealthStatus)

    /// Verifies the adapter's documented contract: a resolver that throws
    /// `KubernetesApiError` causes `probeHealth` to re-throw it — it is NOT
    /// silently mapped to `.unreachable`. Only non-domain errors (NIO, TLS,
    /// unknown) are absorbed into `HealthStatus`.
    func test_endToEnd_resolverThrowsKubernetesApiError_propagatesThrow() async {
        let resolver: SwiftkubeApiAdapter.ClusterResolver = { clusterId in
            throw KubernetesApiError.transportError(
                detail: "ClusterId '\(clusterId.rawValue)' not in synthetic kubeconfig"
            )
        }
        let adapter = SwiftkubeApiAdapter(resolver: resolver)

        do {
            _ = try await adapter.probeHealth(clusterId: ClusterId("missing-cluster"))
            XCTFail("Expected KubernetesApiError.transportError to be thrown")
        } catch KubernetesApiError.transportError(let detail) {
            XCTAssertTrue(
                detail.contains("missing-cluster"),
                "Error detail should reference the missing cluster ID"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
