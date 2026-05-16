// GCPClusterDiscoveryAdapter.swift — infrastructure adapter
// Bounded context: cluster_connectivity / GCP GKE cluster discovery
// DDD role: Adapter (outbound — CloudClusterDiscoveryPort implementation, GCP)
// ADR reference: ADR-0055 § "GCP GKE adapter"
//
// Discovery surface:
// - GET https://cloudresourcemanager.googleapis.com/v1/projects
//   (project enumeration when no scopeHints.gcpProjects)
// - GET https://container.googleapis.com/v1/projects/{project}/locations/{location}/clusters
//   (GKE list; `-` wildcard for all regions and zones).

import ClusterConnectivity
import Foundation
import Logging

// MARK: - GCPClusterDiscoveryAdapter

/// `CloudClusterDiscoveryPort` implementation for GCP GKE.
///
/// Reuses the ADC-derived access token resolved by `GCPExecCredentialAdapter`.
/// Token scope: `https://www.googleapis.com/auth/cloud-platform`. Token
/// expiry is honoured — the resolver returns a fresh token when fewer than
/// 60 s remain.
public struct GCPClusterDiscoveryAdapter: CloudClusterDiscoveryPort, Sendable {

    // MARK: Properties

    /// Async closure returning a valid Bearer token for the supplied scope.
    public typealias TokenResolver = @Sendable (String) async throws -> String

    private let tokenResolver: TokenResolver
    private let session: URLSession
    private let logger: Logger
    private let resourceManagerHost: URL
    private let containerAPIHost: URL

    // MARK: Init

    public init(
        tokenResolver: @escaping TokenResolver,
        session: URLSession = .shared,
        resourceManagerHost: URL = URL(string: "https://cloudresourcemanager.googleapis.com")!,
        containerAPIHost: URL = URL(string: "https://container.googleapis.com")!,
        logger: Logger = Logger(label: "gcp.gke.discovery")
    ) {
        self.tokenResolver = tokenResolver
        self.session = session
        self.resourceManagerHost = resourceManagerHost
        self.containerAPIHost = containerAPIHost
        self.logger = logger
    }

    // MARK: CloudClusterDiscoveryPort

    public func listClusters(
        provider: CloudProvider,
        credentials: CloudCredentialContext,
        scopeHints: CloudScopeHints
    ) async throws -> DiscoveryResult {
        guard provider == .gcp else {
            throw CloudClusterDiscoveryError.notImplemented(provider: provider)
        }

        let token = try await tokenResolver("https://www.googleapis.com/auth/cloud-platform")
        let projects = scopeHints.gcpProjects.isEmpty
            ? try await enumerateProjects(token: token)
            : scopeHints.gcpProjects

        // GCP supports a `-` wildcard for "all locations" in the GKE list path.
        let location = scopeHints.gcpLocations.first ?? "-"

        var allClusters: [ClusterDescriptor] = []
        var warnings: [DiscoveryWarning] = []

        for project in projects {
            do {
                let result = try await listClustersInProject(
                    project: project,
                    location: location,
                    token: token
                )
                allClusters.append(contentsOf: result.clusters)
                warnings.append(contentsOf: result.warnings)
            } catch {
                logger.warning("GKE discovery failed for project \(project): \(error)")
                warnings.append(
                    DiscoveryWarning(
                        provider: .gcp,
                        code: .partialFailure,
                        message: "Project \(project) discovery failed: \(error.localizedDescription)"
                    )
                )
            }
        }

        return DiscoveryResult(clusters: allClusters, warnings: warnings)
    }

    public func materialiseKubeconfig(
        clusterDescriptor: ClusterDescriptor
    ) async throws -> KubeconfigEntry {
        guard clusterDescriptor.provider == .gcp else {
            throw CloudClusterDiscoveryError.notImplemented(provider: clusterDescriptor.provider)
        }

        // GKE exec block uses gke-gcloud-auth-plugin per ADR-0055.
        let exec = KubeconfigUser.ExecConfig(
            apiVersion: "client.authentication.k8s.io/v1beta1",
            command: "gke-gcloud-auth-plugin",
            args: [],
            env: [],
            installHint: "Install gke-gcloud-auth-plugin via `gcloud components install gke-gcloud-auth-plugin`",
            provideClusterInfo: true
        )

        // gke_<project>_<location>_<name> per ADR-0055.
        let projectId = clusterDescriptor.providerMetadata["projectId"] ?? "unknown"
        let location = clusterDescriptor.region ?? clusterDescriptor.providerMetadata["location"] ?? "unknown"
        let contextName = "gke_\(projectId)_\(location)_\(clusterDescriptor.displayName)"

        let cluster = KubeconfigCluster(
            name: contextName,
            server: clusterDescriptor.endpoint.absoluteString,
            certificateAuthorityData: clusterDescriptor.caCertificatePEM.isEmpty
                ? nil
                : clusterDescriptor.caCertificatePEM
        )

        let user = KubeconfigUser(name: contextName, exec: exec)
        let context = KubeconfigContext(
            name: contextName,
            cluster: contextName,
            user: contextName,
            namespace: "default"
        )

        return KubeconfigEntry(cluster: cluster, context: context, user: user)
    }

    // MARK: Private — project enumeration

    private func enumerateProjects(token: String) async throws -> [String] {
        struct ProjectsListResponse: Decodable {
            let projects: [Project]?
            let nextPageToken: String?
        }
        struct Project: Decodable {
            let projectId: String
            let name: String?
            let lifecycleState: String?
        }

        var ids: [String] = []
        var pageToken: String? = nil

        repeat {
            var url = resourceManagerHost
                .appendingPathComponent("v1/projects")
            if let pageToken {
                url = url.appending(queryItem: "pageToken", value: pageToken)
            }
            url = url.appending(queryItem: "pageSize", value: "200")

            let payload: ProjectsListResponse = try await fetch(url: url, token: token, provider: .gcp)
            let active = (payload.projects ?? []).filter { ($0.lifecycleState ?? "ACTIVE") == "ACTIVE" }
            ids.append(contentsOf: active.map(\.projectId))
            pageToken = payload.nextPageToken
        } while pageToken != nil

        return ids
    }

    // MARK: Private — per-project discovery

    private func listClustersInProject(
        project: String,
        location: String,
        token: String
    ) async throws -> DiscoveryResult {
        struct ClustersResponse: Decodable {
            let clusters: [GKECluster]?
            let missingZones: [String]?
        }
        struct GKECluster: Decodable {
            let name: String
            let endpoint: String?
            let masterAuth: MasterAuth?
            let location: String?
            let locations: [String]?
            let currentMasterVersion: String?
            struct MasterAuth: Decodable {
                let clusterCaCertificate: String?
            }
        }

        let url = containerAPIHost
            .appendingPathComponent("v1/projects/\(project)/locations/\(location)/clusters")

        let payload: ClustersResponse = try await fetch(url: url, token: token, provider: .gcp)

        var descriptors: [ClusterDescriptor] = []
        var warnings: [DiscoveryWarning] = []

        for raw in payload.clusters ?? [] {
            guard let endpointHost = raw.endpoint,
                  let endpoint = URL(string: "https://\(endpointHost)") else { continue }

            var metadata: [String: String] = ["projectId": project]
            if let v = raw.currentMasterVersion { metadata["k8sVersion"] = v }
            let regionLabel = raw.location ?? raw.locations?.first

            descriptors.append(
                ClusterDescriptor(
                    id: "projects/\(project)/locations/\(regionLabel ?? "unknown")/clusters/\(raw.name)",
                    displayName: raw.name,
                    provider: .gcp,
                    region: regionLabel,
                    endpoint: endpoint,
                    caCertificatePEM: raw.masterAuth?.clusterCaCertificate ?? "",
                    providerMetadata: metadata
                )
            )
        }

        if let missing = payload.missingZones, !missing.isEmpty {
            warnings.append(
                DiscoveryWarning(
                    provider: .gcp,
                    code: .partialFailure,
                    message: "GKE list missing zones: \(missing.joined(separator: ","))"
                )
            )
        }

        return DiscoveryResult(clusters: descriptors, warnings: warnings)
    }

    // MARK: Private — HTTP fetch

    private func fetch<T: Decodable>(
        url: URL,
        token: String,
        provider: CloudProvider
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudClusterDiscoveryError.transport(
                provider: provider,
                detail: "non-HTTP response"
            )
        }
        switch http.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(T.self, from: data)
        case 401, 403:
            throw CloudClusterDiscoveryError.permissionDenied(
                provider: provider,
                detail: "HTTP \(http.statusCode) — \(String(decoding: data, as: UTF8.self))"
            )
        default:
            throw CloudClusterDiscoveryError.transport(
                provider: provider,
                detail: "HTTP \(http.statusCode) — \(String(decoding: data, as: UTF8.self))"
            )
        }
    }
}

// MARK: - URL query helper

private extension URL {
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
