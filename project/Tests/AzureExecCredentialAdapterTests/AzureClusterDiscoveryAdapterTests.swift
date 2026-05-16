// AzureClusterDiscoveryAdapterTests.swift — unit tests for AzureClusterDiscoveryAdapter
// Coverage: provider mismatch guard, kubeconfig materialisation shape,
//           exec block kubelogin fields, private cluster CA warning.
// No live Azure network calls — all tests exercise value-level logic only.
// ADR reference: ADR-0055 § "Azure AKS adapter"

import XCTest
@testable import AzureExecCredentialAdapter
import ClusterConnectivity
import Foundation

// MARK: - Provider Mismatch Guard

final class AzureClusterDiscoveryAdapterProviderGuardTests: XCTestCase {

    private func makeAdapter() -> AzureClusterDiscoveryAdapter {
        AzureClusterDiscoveryAdapter(
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

    /// Passing a GCP provider must throw `notImplemented`.
    func test_listClusters_wrongProvider_gcp_throwsNotImplemented() async {
        let adapter = makeAdapter()

        do {
            _ = try await adapter.listClusters(
                provider: .gcp,
                credentials: CloudCredentialContext(provider: .gcp),
                scopeHints: .empty
            )
            XCTFail("Expected CloudClusterDiscoveryError.notImplemented")
        } catch CloudClusterDiscoveryError.notImplemented(let provider) {
            XCTAssertEqual(provider, .gcp)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// `materialiseKubeconfig` with a non-Azure descriptor must throw `notImplemented`.
    func test_materialiseKubeconfig_wrongProvider_throwsNotImplemented() async {
        let adapter = makeAdapter()
        let descriptor = ClusterDescriptor(
            id: "arn:aws:eks:us-east-1:123:cluster/foo",
            displayName: "foo",
            provider: .aws,
            region: "us-east-1",
            endpoint: URL(string: "https://example.com")!,
            caCertificatePEM: ""
        )

        do {
            _ = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
            XCTFail("Expected CloudClusterDiscoveryError.notImplemented")
        } catch CloudClusterDiscoveryError.notImplemented(let provider) {
            XCTAssertEqual(provider, .aws)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Kubeconfig Materialisation Shape

final class AzureClusterDiscoveryAdapterKubeconfigTests: XCTestCase {

    private func makeAdapter() -> AzureClusterDiscoveryAdapter {
        AzureClusterDiscoveryAdapter(
            tokenResolver: { _ in "dummy-token" }
        )
    }

    /// A public AKS cluster must produce a kubelogin exec block with correct fields.
    func test_materialiseKubeconfig_publicCluster_kubeloginExecBlock() async throws {
        let adapter = makeAdapter()
        let descriptor = ClusterDescriptor(
            id: "/subscriptions/sub-123/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/my-aks",
            displayName: "my-aks",
            provider: .azure,
            region: "westeurope",
            endpoint: URL(string: "https://my-aks-abcdef.hcp.westeurope.azmk8s.io")!,
            caCertificatePEM: "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t",
            providerMetadata: [
                "subscriptionId": "sub-123",
                "tenantId": "tenant-abc",
                "serverAppID": "6dae42f8-4368-4678-94ff-3960e28e3630",
            ]
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)

        // Cluster entry
        XCTAssertEqual(entry.cluster.name, "my-aks")
        XCTAssertEqual(entry.cluster.server, "https://my-aks-abcdef.hcp.westeurope.azmk8s.io")
        XCTAssertNotNil(entry.cluster.certificateAuthorityData, "CA data must be set for non-empty PEM")

        // User exec block
        let exec = try XCTUnwrap(entry.user.exec, "User must have an exec block")
        XCTAssertEqual(exec.command, "kubelogin", "Azure kubeconfig must use kubelogin")
        XCTAssertEqual(exec.apiVersion, "client.authentication.k8s.io/v1beta1")
        XCTAssertTrue(exec.args.contains("get-token"), "args must include 'get-token'")
        XCTAssertTrue(exec.args.contains("--environment"), "args must include '--environment'")
        XCTAssertTrue(exec.args.contains("--server-id"), "args must include '--server-id'")
        XCTAssertTrue(exec.args.contains("--tenant-id"), "args must include '--tenant-id'")
        XCTAssertTrue(exec.args.contains("tenant-abc"), "tenant-id arg must use metadata value")

        // Context
        XCTAssertEqual(entry.context.cluster, "my-aks")
        XCTAssertEqual(entry.context.user, "my-aks")
        XCTAssertEqual(entry.user.name, "my-aks")
    }

    /// An AKS cluster with no PEM must produce nil CA data.
    func test_materialiseKubeconfig_emptyCA_nilCAData() async throws {
        let adapter = makeAdapter()
        let descriptor = ClusterDescriptor(
            id: "/subscriptions/sub-123/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/private-aks",
            displayName: "private-aks",
            provider: .azure,
            region: "eastus",
            endpoint: URL(string: "https://private.example.com")!,
            caCertificatePEM: ""
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
        XCTAssertNil(entry.cluster.certificateAuthorityData, "Empty PEM should produce nil CA data")
    }

    /// Fallback values must be used when providerMetadata keys are absent.
    func test_materialiseKubeconfig_noMetadata_usesFallbackValues() async throws {
        let adapter = makeAdapter()
        let descriptor = ClusterDescriptor(
            id: "/subscriptions/sub-x/resourceGroups/rg/providers/Microsoft.ContainerService/managedClusters/no-meta-aks",
            displayName: "no-meta-aks",
            provider: .azure,
            region: "northeurope",
            endpoint: URL(string: "https://no-meta.hcp.northeurope.azmk8s.io")!,
            caCertificatePEM: ""
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
        let exec = try XCTUnwrap(entry.user.exec)

        // When no serverAppID is provided, the Microsoft-published default must be used.
        XCTAssertTrue(
            exec.args.contains("6dae42f8-4368-4678-94ff-3960e28e3630"),
            "Default serverAppID must be present when metadata is absent"
        )
    }
}
