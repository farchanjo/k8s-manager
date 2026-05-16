// AzureClusterDiscoveryAdapter.swift — infrastructure adapter
// Bounded context: cluster_connectivity / Azure AKS cluster discovery
// DDD role: Adapter (outbound — CloudClusterDiscoveryPort implementation, Azure)
// ADR reference: ADR-0055 § "Azure AKS adapter"
//
// Discovery surface (Azure Resource Manager REST API):
// - GET /subscriptions?api-version=2022-12-01 (subscription enumeration)
// - GET /subscriptions/{id}/providers/Microsoft.ContainerService/managedClusters
//   ?api-version=2024-02-01 (AKS list, paginated via nextLink)

import ClusterConnectivity
import Foundation
import Logging

// MARK: - AzureClusterDiscoveryAdapter

/// `CloudClusterDiscoveryPort` implementation for Azure AKS.
///
/// Authenticates with the MSAL token already cached by
/// `AzureExecCredentialAdapter`. Token scope used: `https://management.azure.com/.default`.
/// Pagination follows the `nextLink` envelope per Azure REST conventions.
///
/// Private clusters return without a public CA certificate. The adapter
/// emits a `DiscoveryWarning` and ships the descriptor with an empty
/// `caCertificatePEM` so operators can supply the CA out-of-band.
public struct AzureClusterDiscoveryAdapter: CloudClusterDiscoveryPort, Sendable {

    // MARK: Properties

    /// Async closure that resolves a Bearer token for the supplied scope.
    /// Injected so the discovery flow does not import MSAL directly here —
    /// the wired adapter at composition time bridges to MSAL.
    public typealias TokenResolver = @Sendable (String) async throws -> String

    private let tokenResolver: TokenResolver
    private let session: URLSession
    private let logger: Logger
    private let managementHost: URL

    /// Azure Resource Manager API version for AKS resources.
    private static let aksAPIVersion = "2024-02-01"
    /// Azure Resource Manager API version for subscription enumeration.
    private static let subscriptionAPIVersion = "2022-12-01"

    // MARK: Init

    public init(
        tokenResolver: @escaping TokenResolver,
        session: URLSession = .shared,
        managementHost: URL = URL(string: "https://management.azure.com")!,
        logger: Logger = Logger(label: "azure.aks.discovery")
    ) {
        self.tokenResolver = tokenResolver
        self.session = session
        self.managementHost = managementHost
        self.logger = logger
    }

    // MARK: CloudClusterDiscoveryPort

    public func listClusters(
        provider: CloudProvider,
        credentials: CloudCredentialContext,
        scopeHints: CloudScopeHints
    ) async throws -> DiscoveryResult {
        guard provider == .azure else {
            throw CloudClusterDiscoveryError.notImplemented(provider: provider)
        }

        let token = try await tokenResolver("https://management.azure.com/.default")
        let subscriptions = scopeHints.azureSubscriptionIds.isEmpty
            ? try await enumerateSubscriptions(token: token)
            : scopeHints.azureSubscriptionIds

        var allClusters: [ClusterDescriptor] = []
        var warnings: [DiscoveryWarning] = []

        for subscriptionId in subscriptions {
            do {
                let result = try await listClustersInSubscription(
                    subscriptionId: subscriptionId,
                    token: token
                )
                allClusters.append(contentsOf: result.clusters)
                warnings.append(contentsOf: result.warnings)
            } catch {
                logger.warning("AKS discovery failed for subscription \(subscriptionId): \(error)")
                warnings.append(
                    DiscoveryWarning(
                        provider: .azure,
                        code: .partialFailure,
                        message: "Subscription \(subscriptionId) discovery failed: \(error.localizedDescription)"
                    )
                )
            }
        }

        return DiscoveryResult(clusters: allClusters, warnings: warnings)
    }

    public func materialiseKubeconfig(
        clusterDescriptor: ClusterDescriptor
    ) async throws -> KubeconfigEntry {
        guard clusterDescriptor.provider == .azure else {
            throw CloudClusterDiscoveryError.notImplemented(provider: clusterDescriptor.provider)
        }

        // AKS exec block follows the kubelogin pattern per ADR-0055.
        let exec = KubeconfigUser.ExecConfig(
            apiVersion: "client.authentication.k8s.io/v1beta1",
            command: "kubelogin",
            args: [
                "get-token",
                "--environment", "AzurePublicCloud",
                "--server-id", clusterDescriptor.providerMetadata["serverAppID"] ?? "6dae42f8-4368-4678-94ff-3960e28e3630",
                "--client-id", clusterDescriptor.providerMetadata["clientAppID"] ?? "04b07795-8ddb-461a-bbee-02f9e1bf7b46",
                "--tenant-id", clusterDescriptor.providerMetadata["tenantId"] ?? "common",
                "--login", "devicecode",
            ],
            env: [],
            installHint: nil,
            provideClusterInfo: false
        )

        let cluster = KubeconfigCluster(
            name: clusterDescriptor.displayName,
            server: clusterDescriptor.endpoint.absoluteString,
            certificateAuthorityData: clusterDescriptor.caCertificatePEM.isEmpty
                ? nil
                : Data(clusterDescriptor.caCertificatePEM.utf8).base64EncodedString()
        )

        let user = KubeconfigUser(name: clusterDescriptor.displayName, exec: exec)

        let context = KubeconfigContext(
            name: clusterDescriptor.displayName,
            cluster: clusterDescriptor.displayName,
            user: clusterDescriptor.displayName,
            namespace: "default"
        )

        return KubeconfigEntry(cluster: cluster, context: context, user: user)
    }

    // MARK: Private — subscriptions

    private func enumerateSubscriptions(token: String) async throws -> [String] {
        struct SubscriptionListResponse: Decodable {
            let value: [Subscription]
            let nextLink: String?
        }
        struct Subscription: Decodable {
            let subscriptionId: String
        }

        var ids: [String] = []
        var nextURL: URL? = managementHost
            .appendingPathComponent("subscriptions")
            .appending(queryItem: "api-version", value: Self.subscriptionAPIVersion)

        while let url = nextURL {
            let payload: SubscriptionListResponse = try await fetch(url: url, token: token)
            ids.append(contentsOf: payload.value.map(\.subscriptionId))
            nextURL = payload.nextLink.flatMap(URL.init(string:))
        }
        return ids
    }

    // MARK: Private — per-subscription discovery

    private func listClustersInSubscription(
        subscriptionId: String,
        token: String
    ) async throws -> DiscoveryResult {
        struct AKSListResponse: Decodable {
            let value: [AKSCluster]
            let nextLink: String?
        }
        struct AKSCluster: Decodable {
            let id: String
            let name: String
            let location: String
            let properties: Properties?
            struct Properties: Decodable {
                let fqdn: String?
                let azurePortalFqdn: String?
                let privateFQDN: String?
                let kubernetesVersion: String?
            }
        }

        let initialPath = "subscriptions/\(subscriptionId)/providers/Microsoft.ContainerService/managedClusters"
        var nextURL: URL? = managementHost
            .appendingPathComponent(initialPath)
            .appending(queryItem: "api-version", value: Self.aksAPIVersion)

        var descriptors: [ClusterDescriptor] = []
        var warnings: [DiscoveryWarning] = []

        while let url = nextURL {
            let payload: AKSListResponse = try await fetch(url: url, token: token)
            for raw in payload.value {
                let fqdn = raw.properties?.fqdn ?? raw.properties?.privateFQDN
                guard let fqdn,
                      let endpoint = URL(string: "https://\(fqdn)") else { continue }

                var metadata: [String: String] = [
                    "subscriptionId": subscriptionId,
                    "location": raw.location,
                ]
                if let v = raw.properties?.kubernetesVersion { metadata["k8sVersion"] = v }
                if raw.properties?.privateFQDN != nil {
                    warnings.append(
                        DiscoveryWarning(
                            provider: .azure,
                            code: .azurePrivateClusterCAMissing,
                            message: "Private AKS cluster \(raw.name) — supply CA out-of-band before connecting"
                        )
                    )
                }

                descriptors.append(
                    ClusterDescriptor(
                        id: raw.id,
                        displayName: raw.name,
                        provider: .azure,
                        region: raw.location,
                        endpoint: endpoint,
                        caCertificatePEM: "",
                        providerMetadata: metadata
                    )
                )
            }
            nextURL = payload.nextLink.flatMap(URL.init(string:))
        }

        return DiscoveryResult(clusters: descriptors, warnings: warnings)
    }

    // MARK: Private — HTTP fetch

    private func fetch<T: Decodable>(url: URL, token: String) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudClusterDiscoveryError.transport(
                provider: .azure,
                detail: "non-HTTP response"
            )
        }
        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 401, 403:
            throw CloudClusterDiscoveryError.permissionDenied(
                provider: .azure,
                detail: "HTTP \(http.statusCode) — \(String(decoding: data, as: UTF8.self))"
            )
        default:
            throw CloudClusterDiscoveryError.transport(
                provider: .azure,
                detail: "HTTP \(http.statusCode) — \(String(decoding: data, as: UTF8.self))"
            )
        }
    }
}

// MARK: - URL query helper

private extension URL {
    /// Appends a query item to the URL, preserving existing items.
    func appending(queryItem name: String, value: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url ?? self
    }
}
