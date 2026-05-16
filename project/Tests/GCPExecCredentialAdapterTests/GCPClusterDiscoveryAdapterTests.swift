// GCPClusterDiscoveryAdapterTests.swift — unit tests for GCPClusterDiscoveryAdapter
// Coverage: provider mismatch guard, kubeconfig materialisation shape,
//           exec block gke-gcloud-auth-plugin fields, context name format.
// No live GCP network calls — all tests exercise value-level logic only.
// ADR reference: ADR-0055 § "GCP GKE adapter"

import XCTest
@testable import GCPExecCredentialAdapter
import ClusterConnectivity
import Foundation

// MARK: - Provider Mismatch Guard

final class GCPClusterDiscoveryAdapterProviderGuardTests: XCTestCase {

    private func makeAdapter() -> GCPClusterDiscoveryAdapter {
        GCPClusterDiscoveryAdapter(
            tokenResolver: { _ in "dummy-token" }
        )
    }

    /// Passing an AWS provider must throw `notImplemented`.
    func test_listClusters_wrongProvider_aws_throwsNotImplemented() async {
        let adapter = makeAdapter()

        do {
            _ = try await adapter.listClusters(
                provider: .aws,
                credentials: CloudCredentialContext(provider: .aws),
                scopeHints: .empty
            )
            XCTFail("Expected CloudClusterDiscoveryError.notImplemented")
        } catch CloudClusterDiscoveryError.notImplemented(let provider) {
            XCTAssertEqual(provider, .aws)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Passing an Azure provider must throw `notImplemented`.
    func test_listClusters_wrongProvider_azure_throwsNotImplemented() async {
        let adapter = makeAdapter()

        do {
            _ = try await adapter.listClusters(
                provider: .azure,
                credentials: CloudCredentialContext(provider: .azure),
                scopeHints: .empty
            )
            XCTFail("Expected CloudClusterDiscoveryError.notImplemented")
        } catch CloudClusterDiscoveryError.notImplemented(let provider) {
            XCTAssertEqual(provider, .azure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// `materialiseKubeconfig` with a non-GCP descriptor must throw `notImplemented`.
    func test_materialiseKubeconfig_wrongProvider_throwsNotImplemented() async {
        let adapter = makeAdapter()
        let descriptor = ClusterDescriptor(
            id: "/subscriptions/sub/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/aks",
            displayName: "aks",
            provider: .azure,
            region: nil,
            endpoint: URL(string: "https://example.com")!,
            caCertificatePEM: ""
        )

        do {
            _ = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
            XCTFail("Expected CloudClusterDiscoveryError.notImplemented")
        } catch CloudClusterDiscoveryError.notImplemented(let provider) {
            XCTAssertEqual(provider, .azure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Kubeconfig Materialisation Shape

final class GCPClusterDiscoveryAdapterKubeconfigTests: XCTestCase {

    private func makeAdapter() -> GCPClusterDiscoveryAdapter {
        GCPClusterDiscoveryAdapter(
            tokenResolver: { _ in "dummy-token" }
        )
    }

    /// Context name must follow `gke_<project>_<location>_<name>` convention per ADR-0055.
    func test_materialiseKubeconfig_contextNameFormat() async throws {
        let adapter = makeAdapter()
        let descriptor = ClusterDescriptor(
            id: "projects/my-project/locations/us-central1/clusters/prod-cluster",
            displayName: "prod-cluster",
            provider: .gcp,
            region: "us-central1",
            endpoint: URL(string: "https://34.120.0.1")!,
            caCertificatePEM: "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t",
            providerMetadata: ["projectId": "my-project"]
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)

        let expectedContextName = "gke_my-project_us-central1_prod-cluster"
        XCTAssertEqual(entry.cluster.name, expectedContextName)
        XCTAssertEqual(entry.context.name, expectedContextName)
        XCTAssertEqual(entry.context.cluster, expectedContextName)
        XCTAssertEqual(entry.context.user, expectedContextName)
        XCTAssertEqual(entry.user.name, expectedContextName)
    }

    /// Exec block must use `gke-gcloud-auth-plugin` with `provideClusterInfo = true`.
    func test_materialiseKubeconfig_execBlock_gkeGcloudAuthPlugin() async throws {
        let adapter = makeAdapter()
        let descriptor = ClusterDescriptor(
            id: "projects/proj/locations/europe-west1/clusters/gke-cluster",
            displayName: "gke-cluster",
            provider: .gcp,
            region: "europe-west1",
            endpoint: URL(string: "https://10.0.0.1")!,
            caCertificatePEM: "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t",
            providerMetadata: ["projectId": "proj"]
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
        let exec = try XCTUnwrap(entry.user.exec, "User must have an exec block")

        XCTAssertEqual(exec.command, "gke-gcloud-auth-plugin")
        XCTAssertEqual(exec.apiVersion, "client.authentication.k8s.io/v1beta1")
        XCTAssertTrue(exec.provideClusterInfo, "provideClusterInfo must be true for GKE")
        XCTAssertNotNil(exec.installHint, "installHint must be present for gke-gcloud-auth-plugin")
    }

    /// Server endpoint must be preserved verbatim from the descriptor.
    func test_materialiseKubeconfig_serverEndpointPreserved() async throws {
        let adapter = makeAdapter()
        let endpointString = "https://34.120.99.200"
        let descriptor = ClusterDescriptor(
            id: "projects/p/locations/us-west1/clusters/c",
            displayName: "c",
            provider: .gcp,
            region: "us-west1",
            endpoint: URL(string: endpointString)!,
            caCertificatePEM: "",
            providerMetadata: ["projectId": "p"]
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
        XCTAssertEqual(entry.cluster.server, endpointString)
    }

    /// When providerMetadata lacks `projectId`, `"unknown"` must be used as fallback
    /// rather than crashing.
    func test_materialiseKubeconfig_missingProjectId_usesUnknownFallback() async throws {
        let adapter = makeAdapter()
        let descriptor = ClusterDescriptor(
            id: "projects/unknown/locations/us-east1/clusters/orphan",
            displayName: "orphan",
            provider: .gcp,
            region: "us-east1",
            endpoint: URL(string: "https://10.10.10.1")!,
            caCertificatePEM: ""
            // No providerMetadata — projectId absent
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
        // Must not crash. Context name must contain "unknown" as the project segment.
        XCTAssertTrue(
            entry.cluster.name.hasPrefix("gke_unknown_"),
            "Context name must start with 'gke_unknown_' when projectId metadata is absent"
        )
    }
}
