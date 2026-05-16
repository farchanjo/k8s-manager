// Domain/Release.swift — helm_management bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/helm_management/schemas/release.cue
// ADR ref: ADR-0015

import Foundation
import SharedKernel

// MARK: - Release

/// Aggregate root representing a single Helm release revision.
///
/// Materialised by decoding a Kubernetes Secret of type `helm.sh/release.v1`
/// written by the Helm 3 secret storage driver. Carries the full decoded state
/// for one revision: chart metadata, user-supplied values, rendered manifest,
/// declared hooks, lifecycle info, and the source Secret name.
///
/// Multiple `Release` values with the same `name` and `namespace` but
/// different `version` integers represent the revision history of a single
/// logical Helm release. Grouping and history projection are the
/// responsibility of `ReleaseReaderActor`.
///
/// **Security invariant:** a `Release` MUST NOT be materialised from a Secret
/// that fails the `release_decoder_invariants` Rego policy. In particular,
/// `manifestYAML` must not contain PEM-encoded certificate or private-key
/// blocks — the `ReleaseStorePort` adapter is responsible for this check.
public struct Release: Hashable, Sendable, Codable {
    /// UUIDv7 generated deterministically from (kubernetesContextId, namespace,
    /// name, version) at decode time. Stable across application restarts for
    /// the same revision Secret.
    public let id: UUID

    /// UUIDv7 of the active cluster context provided by
    /// `cluster_connectivity` at decode time.
    public let kubernetesContextId: UUID

    /// Helm release name. Sourced from the decoded release JSON payload,
    /// not from the Secret name. Conforms to Helm naming rules:
    /// lowercase alphanumeric with dots and hyphens, 1–53 characters.
    public let name: String

    /// Kubernetes namespace in which this release was deployed.
    public let namespace: String

    /// Helm revision number for this release instance. Starts at 1 for the
    /// initial install. Incremented by 1 on each upgrade or rollback.
    public let version: Int

    /// Helm release status at the time this revision was last written.
    public let status: ReleaseStatus

    /// Metadata of the chart used to render this release revision.
    public let chart: ChartMetadata

    /// Lifecycle timestamps and human-readable description for this revision.
    public let info: ReleaseInfo

    /// Full rendered manifest YAML that Helm applied to the cluster.
    ///
    /// The concatenation of all rendered template outputs separated by
    /// YAML document separators. May be empty for releases installed with
    /// no templates. Must not contain PEM-encoded certificate blocks
    /// (enforced by the Rego invariants policy).
    public let manifestYAML: String

    /// JSON serialisation of the user-supplied values (the `config` field
    /// in the Helm release JSON). `"{}"` represents an install with no overrides.
    public let valuesJSON: String

    /// Hook manifests declared by the chart.
    public let hooks: [HookManifest]

    /// RFC3339 timestamp of the last-deployed time for this specific revision.
    /// Sourced from `info.lastDeployed`.
    public let modifiedAtRFC3339: String

    /// Name of the Kubernetes Secret from which this aggregate was decoded.
    /// Convention: `"sh.helm.release.v1.<name>.v<version>"`.
    public let sourceSecretName: String

    public init(
        id: UUID,
        kubernetesContextId: UUID,
        name: String,
        namespace: String,
        version: Int,
        status: ReleaseStatus,
        chart: ChartMetadata,
        info: ReleaseInfo,
        manifestYAML: String,
        valuesJSON: String,
        hooks: [HookManifest],
        modifiedAtRFC3339: String,
        sourceSecretName: String
    ) {
        precondition(version >= 1, "Helm revision numbers start at 1")
        self.id = id
        self.kubernetesContextId = kubernetesContextId
        self.name = name
        self.namespace = namespace
        self.version = version
        self.status = status
        self.chart = chart
        self.info = info
        self.manifestYAML = manifestYAML
        self.valuesJSON = valuesJSON
        self.hooks = hooks
        self.modifiedAtRFC3339 = modifiedAtRFC3339
        self.sourceSecretName = sourceSecretName
    }
}
