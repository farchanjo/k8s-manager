// AWSClusterDiscoveryAdapterTests.swift — unit tests for AWSClusterDiscoveryAdapter
// Coverage: provider mismatch guard, ARN parsing, kubeconfig materialisation shape,
//           exec block field correctness.
// No real AWS network calls — all tests exercise value-level logic only.
// ADR reference: ADR-0055 § "AWS EKS adapter"

@preconcurrency import SotoCore
import XCTest
@testable import AWSExecCredentialAdapter
import ClusterConnectivity
import Foundation

// MARK: - Helpers

/// Constructs a shared `AWSClient` with empty credentials for use in tests
/// that need to call `materialiseKubeconfig` (which only exercises ARN parsing,
/// never an actual AWS network call).
private func makeTestClient() -> AWSClient {
    AWSClient(credentialProvider: .empty)
}

// MARK: - Provider Mismatch Guard

final class AWSClusterDiscoveryAdapterProviderGuardTests: XCTestCase {

    /// Passing a non-AWS provider must throw `notImplemented`.
    func test_listClusters_wrongProvider_azure_throwsNotImplemented() async throws {
        let client = makeTestClient()
        addTeardownBlock { try? await client.shutdown() }
        let adapter = AWSClusterDiscoveryAdapter(client: client)

        do {
            _ = try await adapter.listClusters(
                provider: .azure,
                credentials: CloudCredentialContext(provider: .azure),
                scopeHints: .empty
            )
            XCTFail("Expected CloudClusterDiscoveryError.notImplemented to be thrown")
        } catch CloudClusterDiscoveryError.notImplemented(let provider) {
            XCTAssertEqual(provider, .azure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Passing GCP provider must also throw `notImplemented`.
    func test_listClusters_wrongProvider_gcp_throwsNotImplemented() async throws {
        let client = makeTestClient()
        addTeardownBlock { try? await client.shutdown() }
        let adapter = AWSClusterDiscoveryAdapter(client: client)

        do {
            _ = try await adapter.listClusters(
                provider: .gcp,
                credentials: CloudCredentialContext(provider: .gcp),
                scopeHints: .empty
            )
            XCTFail("Expected CloudClusterDiscoveryError.notImplemented to be thrown")
        } catch CloudClusterDiscoveryError.notImplemented(let provider) {
            XCTAssertEqual(provider, .gcp)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// `materialiseKubeconfig` with a non-AWS descriptor must throw `notImplemented`.
    func test_materialiseKubeconfig_wrongProvider_throwsNotImplemented() async throws {
        let client = makeTestClient()
        addTeardownBlock { try? await client.shutdown() }
        let adapter = AWSClusterDiscoveryAdapter(client: client)

        let descriptor = ClusterDescriptor(
            id: "projects/my-project/locations/us-central1/clusters/my-cluster",
            displayName: "my-cluster",
            provider: .gcp,
            region: "us-central1",
            endpoint: URL(string: "https://1.2.3.4")!,
            caCertificatePEM: ""
        )

        do {
            _ = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
            XCTFail("Expected CloudClusterDiscoveryError.notImplemented")
        } catch CloudClusterDiscoveryError.notImplemented(let provider) {
            XCTAssertEqual(provider, .gcp)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - ARN Parsing (via kubeconfig materialisation)

final class AWSClusterDiscoveryAdapterARNTests: XCTestCase {

    /// A well-formed EKS ARN must produce a kubeconfig entry with matching
    /// cluster name, exec command, and region/cluster-name args.
    func test_materialiseKubeconfig_validARN_producesCorrectEntry() async throws {
        let client = makeTestClient()
        addTeardownBlock { try? await client.shutdown() }
        let adapter = AWSClusterDiscoveryAdapter(client: client)

        let arn = "arn:aws:eks:eu-west-1:123456789012:cluster/my-production-cluster"
        let descriptor = ClusterDescriptor(
            id: arn,
            displayName: "my-production-cluster",
            provider: .aws,
            region: "eu-west-1",
            endpoint: URL(string: "https://AABBCC.gr7.eu-west-1.eks.amazonaws.com")!,
            caCertificatePEM: "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)

        // Cluster name must equal the ARN (ADR-0055).
        XCTAssertEqual(entry.cluster.name, arn)
        XCTAssertEqual(entry.cluster.server, "https://AABBCC.gr7.eu-west-1.eks.amazonaws.com")
        XCTAssertNotNil(entry.cluster.certificateAuthorityData, "CA data must be present when PEM is non-empty")

        // Exec block fields.
        let exec = try XCTUnwrap(entry.user.exec, "User must have an exec block")
        XCTAssertEqual(exec.command, "aws")
        XCTAssertTrue(exec.args.contains("eks"), "args must include 'eks'")
        XCTAssertTrue(exec.args.contains("get-token"), "args must include 'get-token'")
        XCTAssertTrue(exec.args.contains("--cluster-name"), "args must include '--cluster-name'")
        XCTAssertTrue(exec.args.contains("my-production-cluster"), "args must include cluster name")
        XCTAssertTrue(exec.args.contains("--region"), "args must include '--region'")
        XCTAssertTrue(exec.args.contains("eu-west-1"), "args must include region")
        XCTAssertEqual(exec.apiVersion, "client.authentication.k8s.io/v1beta1")

        // Context must reference cluster + user by the same name (ARN).
        XCTAssertEqual(entry.context.cluster, arn)
        XCTAssertEqual(entry.context.user, arn)
        XCTAssertEqual(entry.user.name, arn)
    }

    /// A malformed ARN must throw a transport error, not crash.
    func test_materialiseKubeconfig_malformedARN_throwsTransport() async throws {
        let client = makeTestClient()
        addTeardownBlock { try? await client.shutdown() }
        let adapter = AWSClusterDiscoveryAdapter(client: client)

        let descriptor = ClusterDescriptor(
            id: "not-an-arn",
            displayName: "bad",
            provider: .aws,
            region: "us-east-1",
            endpoint: URL(string: "https://example.com")!,
            caCertificatePEM: ""
        )

        do {
            _ = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
            XCTFail("Expected transport error for malformed ARN")
        } catch CloudClusterDiscoveryError.transport(let provider, let detail) {
            XCTAssertEqual(provider, .aws)
            XCTAssertTrue(detail.contains("malformed"), "Detail must mention 'malformed': \(detail)")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    /// ARN with no cluster name segment must throw transport.
    func test_materialiseKubeconfig_arnMissingClusterName_throwsTransport() async throws {
        let client = makeTestClient()
        addTeardownBlock { try? await client.shutdown() }
        let adapter = AWSClusterDiscoveryAdapter(client: client)

        let descriptor = ClusterDescriptor(
            id: "arn:aws:eks:us-east-1:123456789012:cluster",   // missing /name
            displayName: "missing",
            provider: .aws,
            region: "us-east-1",
            endpoint: URL(string: "https://example.com")!,
            caCertificatePEM: ""
        )

        do {
            _ = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
            XCTFail("Expected transport error for ARN missing cluster name")
        } catch CloudClusterDiscoveryError.transport(_, _) {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// Empty CA PEM must result in `nil` certificateAuthorityData (private cluster path).
    func test_materialiseKubeconfig_emptyCAProducesNilData() async throws {
        let client = makeTestClient()
        addTeardownBlock { try? await client.shutdown() }
        let adapter = AWSClusterDiscoveryAdapter(client: client)

        let descriptor = ClusterDescriptor(
            id: "arn:aws:eks:us-east-1:123456789012:cluster/private-cluster",
            displayName: "private-cluster",
            provider: .aws,
            region: "us-east-1",
            endpoint: URL(string: "https://private.example.com")!,
            caCertificatePEM: ""
        )

        let entry = try await adapter.materialiseKubeconfig(clusterDescriptor: descriptor)
        XCTAssertNil(entry.cluster.certificateAuthorityData, "Empty PEM should produce nil CA data")
    }
}
