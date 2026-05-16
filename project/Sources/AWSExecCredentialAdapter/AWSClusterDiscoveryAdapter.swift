// AWSClusterDiscoveryAdapter.swift — infrastructure adapter
// Bounded context: cluster_connectivity / AWS EKS cluster discovery
// DDD role: Adapter (outbound — CloudClusterDiscoveryPort implementation, AWS)
// ADR reference: ADR-0055 § "AWS EKS adapter"
//
// Discovery surface:
// - `eks:ListClusters` (paginated) per region.
// - `eks:DescribeCluster` per cluster name.
// - `ec2:DescribeRegions` to resolve opt-in regions when no scope hint set.
// Subprocess-free: satisfies ADR-0001.

@preconcurrency import SotoCore
@preconcurrency import SotoEC2
@preconcurrency import SotoEKS
import ClusterConnectivity
import Foundation
import Logging

// MARK: - AWSClusterDiscoveryAdapter

/// `CloudClusterDiscoveryPort` implementation for AWS EKS.
///
/// Uses the same `AWSClient` credential chain as `AWSExecCredentialAdapter`
/// (ADR-0018) so operators never re-authenticate. Region resolution falls
/// back to the static standard-partition list when `ec2:DescribeRegions`
/// is denied; a `DiscoveryWarning` is surfaced in the result.
public struct AWSClusterDiscoveryAdapter: CloudClusterDiscoveryPort, Sendable {

    // MARK: Properties

    /// Soto AWS client. Shared across calls so credential resolution caches
    /// effectively. Owners are responsible for `shutdown()` at app exit.
    private let client: AWSClient

    /// Logger scoped to the adapter for diagnostic traces.
    private let logger: Logger

    /// Static fallback region list used when `ec2:DescribeRegions` is denied.
    /// Restricted to the standard (`aws`) partition; govcloud and CN
    /// partitions are excluded per ADR-0055.
    private static let staticFallbackRegions: [String] = [
        "us-east-1", "us-east-2", "us-west-1", "us-west-2",
        "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1", "eu-north-1",
        "ap-south-1", "ap-northeast-1", "ap-northeast-2", "ap-northeast-3",
        "ap-southeast-1", "ap-southeast-2", "ap-southeast-3",
        "ca-central-1", "sa-east-1", "af-south-1",
    ]

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - client: Soto AWS client configured with the operator's credential
    ///     chain (environment, `~/.aws/credentials`, SSO, etc.).
    ///   - logger: Structured logger forwarded to the discovery flow.
    public init(client: AWSClient, logger: Logger = Logger(label: "aws.eks.discovery")) {
        self.client = client
        self.logger = logger
    }

    // MARK: CloudClusterDiscoveryPort

    public func listClusters(
        provider: CloudProvider,
        credentials: CloudCredentialContext,
        scopeHints: CloudScopeHints
    ) async throws -> DiscoveryResult {
        guard provider == .aws else {
            throw CloudClusterDiscoveryError.notImplemented(provider: provider)
        }

        let resolution = try await resolveRegions(scopeHints: scopeHints)
        var allClusters: [ClusterDescriptor] = []
        var warnings: [DiscoveryWarning] = resolution.warnings

        for region in resolution.regions {
            do {
                let regional = try await listClustersInRegion(region)
                allClusters.append(contentsOf: regional)
            } catch let error as AWSErrorType {
                logger.warning("EKS discovery failed in region \(region): \(error)")
                warnings.append(
                    DiscoveryWarning(
                        provider: .aws,
                        code: .partialFailure,
                        message: "EKS discovery in \(region) failed: \(error.errorCode)"
                    )
                )
            } catch {
                logger.warning("EKS discovery failed in region \(region): \(error)")
                warnings.append(
                    DiscoveryWarning(
                        provider: .aws,
                        code: .partialFailure,
                        message: "EKS discovery in \(region) failed: \(error.localizedDescription)"
                    )
                )
            }
        }

        return DiscoveryResult(clusters: allClusters, warnings: warnings)
    }

    public func materialiseKubeconfig(
        clusterDescriptor: ClusterDescriptor
    ) async throws -> KubeconfigEntry {
        guard clusterDescriptor.provider == .aws else {
            throw CloudClusterDiscoveryError.notImplemented(provider: clusterDescriptor.provider)
        }

        // The descriptor id is the ARN per ADR-0055 § "Kubeconfig materialisation rules".
        // Parse region and cluster name from the ARN for the exec-block args.
        let parsed = try Self.parseEKSARN(clusterDescriptor.id)

        let cluster = KubeconfigCluster(
            name: clusterDescriptor.id,
            server: clusterDescriptor.endpoint.absoluteString,
            certificateAuthorityData: clusterDescriptor.caCertificatePEM.isEmpty
                ? nil
                : Self.encodeBase64(clusterDescriptor.caCertificatePEM)
        )

        let exec = KubeconfigUser.ExecConfig(
            apiVersion: "client.authentication.k8s.io/v1beta1",
            command: "aws",
            args: [
                "eks", "get-token",
                "--cluster-name", parsed.clusterName,
                "--region", parsed.region,
            ],
            env: [],
            installHint: nil,
            provideClusterInfo: false
        )

        let user = KubeconfigUser(name: clusterDescriptor.id, exec: exec)

        let context = KubeconfigContext(
            name: clusterDescriptor.id,
            cluster: clusterDescriptor.id,
            user: clusterDescriptor.id,
            namespace: "default"
        )

        return KubeconfigEntry(cluster: cluster, context: context, user: user)
    }

    // MARK: Private — region resolution

    private struct RegionResolution {
        let regions: [String]
        let warnings: [DiscoveryWarning]
    }

    private func resolveRegions(
        scopeHints: CloudScopeHints
    ) async throws -> RegionResolution {
        if !scopeHints.awsRegions.isEmpty {
            return RegionResolution(regions: scopeHints.awsRegions, warnings: [])
        }
        do {
            let ec2 = EC2(client: client, region: .useast1)
            let response = try await ec2.describeRegions(
                .init(allRegions: false)
            )
            let regions = (response.regions ?? [])
                .compactMap(\.regionName)
                .sorted()
            if regions.isEmpty {
                return RegionResolution(
                    regions: Self.staticFallbackRegions,
                    warnings: [
                        DiscoveryWarning(
                            provider: .aws,
                            code: .awsRegionListUnavailable,
                            message: "DescribeRegions returned no opted-in regions; using static fallback list"
                        )
                    ]
                )
            }
            return RegionResolution(regions: regions, warnings: [])
        } catch {
            logger.info("ec2:DescribeRegions denied — falling back to static region list (\(error))")
            return RegionResolution(
                regions: Self.staticFallbackRegions,
                warnings: [
                    DiscoveryWarning(
                        provider: .aws,
                        code: .awsRegionListUnavailable,
                        message: "DescribeRegions unavailable; using static standard-partition region list"
                    )
                ]
            )
        }
    }

    // MARK: Private — per-region discovery

    private func listClustersInRegion(_ regionRaw: String) async throws -> [ClusterDescriptor] {
        let region = Region(awsRegionName: regionRaw)
        let eks = EKS(client: client, region: region)

        // Paginate ListClusters.
        var names: [String] = []
        var nextToken: String? = nil
        repeat {
            let response = try await eks.listClusters(
                .init(maxResults: 100, nextToken: nextToken)
            )
            names.append(contentsOf: response.clusters ?? [])
            nextToken = response.nextToken
        } while nextToken != nil

        // DescribeCluster per name.
        var descriptors: [ClusterDescriptor] = []
        for name in names {
            do {
                let describe = try await eks.describeCluster(.init(name: name))
                guard let summary = describe.cluster,
                      let arn = summary.arn,
                      let endpointStr = summary.endpoint,
                      let endpoint = URL(string: endpointStr) else { continue }

                let caPEM = summary.certificateAuthority?.data ?? ""

                var metadata: [String: String] = [:]
                if let version = summary.version { metadata["k8sVersion"] = version }
                if let status = summary.status?.rawValue { metadata["status"] = status }
                if let arnRegion = Self.parseRegionFromARN(arn) { metadata["region"] = arnRegion }

                descriptors.append(
                    ClusterDescriptor(
                        id: arn,
                        displayName: name,
                        provider: .aws,
                        region: regionRaw,
                        endpoint: endpoint,
                        caCertificatePEM: caPEM,
                        providerMetadata: metadata
                    )
                )
            } catch {
                logger.warning("DescribeCluster failed for \(name) in \(regionRaw): \(error)")
            }
        }
        return descriptors
    }

    // MARK: Private — ARN parsing

    private struct ParsedEKSARN {
        let region: String
        let clusterName: String
    }

    /// Parses an EKS cluster ARN into the region + cluster name segments.
    /// ARN format: `arn:aws:eks:<region>:<account>:cluster/<name>`.
    private static func parseEKSARN(_ arn: String) throws -> ParsedEKSARN {
        let parts = arn.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 6, parts[2] == "eks" else {
            throw CloudClusterDiscoveryError.transport(
                provider: .aws,
                detail: "malformed EKS ARN: \(arn)"
            )
        }
        let region = parts[3]
        let resource = parts[5]
        guard let slash = resource.firstIndex(of: "/") else {
            throw CloudClusterDiscoveryError.transport(
                provider: .aws,
                detail: "EKS ARN resource segment missing cluster name: \(arn)"
            )
        }
        let clusterName = String(resource[resource.index(after: slash)...])
        return ParsedEKSARN(region: region, clusterName: clusterName)
    }

    private static func parseRegionFromARN(_ arn: String) -> String? {
        let parts = arn.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 4 else { return nil }
        return String(parts[3])
    }

    // MARK: Private — base64 helpers

    private static func encodeBase64(_ pem: String) -> String {
        // EKS returns CA data already base64-encoded; if the descriptor was
        // populated from a parsed PEM block we re-encode. Idempotent because
        // we Base64 the raw UTF-8 bytes of the PEM text.
        Data(pem.utf8).base64EncodedString()
    }
}
