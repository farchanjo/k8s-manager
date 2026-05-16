// Domain/CloudProvider.swift — cluster_connectivity bounded context
// DDD role: ValueObject
// ADR ref: ADR-0055 (Cloud provider cluster discovery)

import Foundation

// MARK: - CloudProvider

/// Discriminator for the three first-class cloud providers supported by the
/// Cluster Connectivity discovery surface.
///
/// Each provider maps to a sibling exec-credential adapter (ADR-0018) and a
/// matching `CloudClusterDiscoveryPort` adapter (ADR-0055). DigitalOcean DOKS
/// is intentionally absent — discovery for DOKS is deferred per ADR-0055.
public enum CloudProvider: String, Sendable, Hashable, Codable, CaseIterable {
    /// Amazon Web Services / Elastic Kubernetes Service (EKS).
    case aws
    /// Microsoft Azure / Azure Kubernetes Service (AKS).
    case azure
    /// Google Cloud Platform / Google Kubernetes Engine (GKE).
    case gcp

    /// Operator-facing label used in cluster-strip provider groupings and
    /// Welcome-tab action descriptions.
    public var displayName: String {
        switch self {
        case .aws:   return "AWS EKS"
        case .azure: return "Azure AKS"
        case .gcp:   return "GCP GKE"
        }
    }
}

// MARK: - CloudCredentialContext

/// Opaque credential context resolved by the ADR-0018 credential chain and
/// passed through to a `CloudClusterDiscoveryPort` invocation.
///
/// The discovery adapter and its sibling exec-credential adapter share the
/// same resolution path; the domain core never inspects the payload.
public struct CloudCredentialContext: Sendable, Hashable, Codable {
    /// Provider that resolved the credential.
    public let provider: CloudProvider

    /// Free-form key/value bag for adapter-specific payload (profile name,
    /// subscription id, project id, token, etc.). Empty for adapters that
    /// resolve credentials lazily on first call.
    public let metadata: [String: String]

    public init(provider: CloudProvider, metadata: [String: String] = [:]) {
        self.provider = provider
        self.metadata = metadata
    }
}

// MARK: - CloudScopeHints

/// Optional filters applied at discovery time to restrict which regions,
/// subscriptions, or projects are enumerated.
///
/// All fields default to an empty array which means "use the provider's
/// default scope discovery flow" (e.g. `ec2:DescribeRegions` for AWS,
/// `GET /subscriptions` for Azure, the Resource Manager API for GCP).
public struct CloudScopeHints: Sendable, Hashable, Codable {
    /// AWS regions to enumerate. Empty = all opted-in regions.
    public var awsRegions: [String]
    /// Optional named AWS profile from `~/.aws/credentials`. `nil` = default.
    public var awsProfile: String?
    /// Azure subscription ids to enumerate. Empty = every accessible subscription.
    public var azureSubscriptionIds: [String]
    /// GCP projects to enumerate. Empty = every accessible project.
    public var gcpProjects: [String]
    /// GCP locations (regions or zones). Empty = pass `-` wildcard to GKE API.
    public var gcpLocations: [String]

    public init(
        awsRegions: [String] = [],
        awsProfile: String? = nil,
        azureSubscriptionIds: [String] = [],
        gcpProjects: [String] = [],
        gcpLocations: [String] = []
    ) {
        self.awsRegions = awsRegions
        self.awsProfile = awsProfile
        self.azureSubscriptionIds = azureSubscriptionIds
        self.gcpProjects = gcpProjects
        self.gcpLocations = gcpLocations
    }

    /// Default-empty instance used by call sites that pass no hints.
    public static let empty = CloudScopeHints()
}
