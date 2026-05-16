# ADR-0055 — Cloud provider cluster discovery (AWS, Azure, GCP)

- Status — Proposed
- Date — 2026-05-16
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Refines — ADR-0018 (native cloud credential resolution), ADR-0051 (multi-cluster workspace),
  ADR-0054 (welcome tab and cluster-acquisition entry surface)
- Tags — cloud-discovery, aws, azure, gcp, eks, aks, gke, kubeconfig, hexagonal,
  cluster-connectivity

## Context and problem statement

ADR-0018 defines native in-process credential adapters for AWS EKS, GCP GKE, and Azure AKS
(`AWSExecCredentialAdapter`, `GCPExecCredentialAdapter`, `AzureExecCredentialAdapter`). Those
adapters handle the token-refresh half of the cloud-cluster relationship: given a kubeconfig entry
with an exec block, they resolve a bearer token.

The discovery half — enumerating which clusters exist in a cloud account and synthesising a
kubeconfig entry for each — is not yet specified. Operators who manage a fleet of EKS, AKS, or GKE
clusters today must maintain their kubeconfig files by hand or rely on the `aws`, `gcloud`, or `az`
CLIs. This contradicts ADR-0001 (no subprocess dependency) and contradicts the five-action cluster-
acquisition surface defined in ADR-0054 (welcome tab).

The recording analysis in `feature-gap-analysis-lens-prism-ai.md` (items R12, R13, R12a) identifies
"Add Clusters from AWS" and "Add Clusters from AKS" as first-class welcome-tab actions in Lens, and
notes the absence of equivalent GKE discovery in K8S-Manager.

This ADR defines the port contracts, provider adapter shapes, credential acquisition rules,
kubeconfig materialisation rules, and scoping boundaries for the cloud-cluster discovery feature
across all three providers (AWS EKS, Azure AKS, GCP GKE).

## Decision drivers

- **Credential boundary minimisation** — discovery adapters must request only the minimum IAM /
  RBAC / IAM-policy permissions required to enumerate and describe clusters. No management-plane
  write permissions, no data-plane access, no broad resource listing beyond the discovery scope.
- **Subprocess-free** — discovery must not invoke `aws`, `az`, `gcloud`, `kubectl`, or any external
  binary. Network calls use URLSession (already permitted by the `com.apple.security.network.client`
  entitlement acquired in ADR-0018).
- **Hexagonal isolation** — discovery logic lives in the adapter layer. The domain core is
  unchanged; it sees only the `CloudClusterDiscoveryPort` interface and the
  `ClusterDescriptor` / `KubeconfigEntry` value types.
- **Credential reuse** — discovery adapters must reuse the same credential chain used by
  `AWSExecCredentialAdapter`, `GCPExecCredentialAdapter`, and `AzureExecCredentialAdapter`
  (ADR-0018). No second authentication prompt for operators who already have credentials configured.
- **Provider-scoped pickers** — operators managing multiple AWS accounts, Azure subscriptions, or
  GCP projects must be able to scope discovery to a specific account/subscription/project without
  modifying environment variables or kubeconfig files.
- **Partial failure tolerance** — if one cluster's materialisation fails (e.g. a region is
  unreachable), the remaining clusters must still be importable.
- **Sandbox and App Store compatibility** — no additional entitlements beyond those already granted
  in ADR-0018.

## Considered options

- **Option A** — Per-provider native SDK adapters implementing a shared
  `CloudClusterDiscoveryPort` protocol (chosen).
- **Option B** — Cloud CLI invocation via subprocess (aws eks list-clusters, az aks list,
  gcloud container clusters list).
- **Option C** — Unified cloud-abstraction library (e.g. Pulumi Automation API, Crossplane) wrapping
  all three providers behind a single discovery surface.

## Decision outcome

Chosen option — **Option A**, because:

- It is the only option compatible with subprocess-free distribution (ADR-0001, ADR-0018).
- It allows each provider adapter to be implemented and shipped independently, matching the
  incremental-delivery driver from ADR-0018.
- Option B permanently blocks App Store distribution and reintroduces the binary-version fragility
  that ADR-0018 eliminates for token refresh.
- Option C introduces a large indirect dependency with its own update cadence and licensing
  constraints, for a surface that is already well-understood at the raw HTTP level.

The decision outcome is: **K8S-Manager implements cloud cluster discovery as a set of provider
adapters behind a shared `CloudClusterDiscoveryPort` protocol; each adapter uses the same
credential chain as its ADR-0018 sibling; kubeconfig materialisation produces an entry that is
structurally identical to what the respective cloud CLI would produce; DigitalOcean DOKS discovery
is deferred.**

## Port contracts (Hexagonal)

### CloudClusterDiscoveryPort

Declared in:
`ClusterConnectivity/Sources/ClusterConnectivity/Ports/CloudClusterDiscoveryPort.swift`

```
protocol CloudClusterDiscoveryPort: Sendable {

    /// List all clusters reachable with the supplied credentials.
    /// provider: one of .aws, .azure, .gcp
    /// credentials: opaque credential context resolved by the ADR-0018 credential chain
    /// scopeHints: optional region / subscription / project filter (see per-provider rules)
    func listClusters(
        provider: CloudProvider,
        credentials: CloudCredentialContext,
        scopeHints: CloudScopeHints
    ) async throws -> [ClusterDescriptor]

    /// Materialise a KubeconfigEntry for the given descriptor.
    /// The returned entry is ready for merge into the operator's kubeconfig aggregate.
    /// Throws if the cluster's management endpoint is unreachable or certificate
    /// retrieval fails.
    func materialiseKubeconfig(
        clusterDescriptor: ClusterDescriptor
    ) async throws -> KubeconfigEntry
}
```

### Supporting value types

`CloudProvider` is an enum with cases `aws`, `azure`, `gcp`.

`CloudCredentialContext` is a `Sendable` struct carrying whatever the credential chain resolved
(SigV4 credential tuple for AWS, MSAL token for Azure, ADC-derived access token for GCP). It is
opaque to the domain core; the discovery adapter and its ADR-0018 sibling share the same
resolution path.

`CloudScopeHints` is a `Sendable` struct:

```
struct CloudScopeHints: Sendable {
    var awsRegions: [String]          // empty = all accessible regions
    var azureSubscriptionIds: [String] // empty = all accessible subscriptions
    var gcpProjects: [String]          // empty = all accessible projects
    var gcpLocations: [String]         // empty = all regions and zones
}
```

`ClusterDescriptor` is a `Sendable` struct:

```
struct ClusterDescriptor: Sendable, Identifiable {
    let id: String               // provider-native identifier
    let displayName: String
    let provider: CloudProvider
    let region: String?          // AWS region / GCP location; nil for Azure (resource group used)
    let endpoint: URL            // management API endpoint (HTTPS)
    let caCertificatePEM: String // cluster CA certificate in PEM format
    let providerMetadata: [String: String] // provider-specific pass-through
}
```

`KubeconfigEntry` is a `Sendable` struct that maps to the kubeconfig cluster + context + user
triple ready for insertion into the in-memory `KubeconfigAggregate` (defined in
`cluster_connectivity` bounded context).

## Provider-specific adapter shapes

### AWS EKS adapter — `AWSClusterDiscoveryAdapter`

Implemented in:
`ClusterConnectivity/Sources/Adapters/AWS/AWSClusterDiscoveryAdapter.swift`

Discovery calls (both use the existing soto 7.14.0 client, credential chain identical to
`AWSExecCredentialAdapter`):

- `eks:ListClusters` (paginated) — iterates through all EKS clusters in the target region.
  Required IAM permission: `eks:ListClusters`.
- `eks:DescribeCluster` — called for each cluster name returned by `ListClusters`. Returns the
  cluster endpoint, CA certificate data, Kubernetes version, and tags. Required IAM permission:
  `eks:DescribeCluster`.

No other EKS or IAM API is called during discovery.

The adapter iterates `scopeHints.awsRegions` if non-empty; otherwise it iterates the region list
returned by `ec2:DescribeRegions` filtered to regions where the operator's account is opted-in.
`ec2:DescribeRegions` requires `ec2:DescribeRegions` IAM permission.

When `ec2:DescribeRegions` is denied, the adapter falls back to the static partition region list
for `aws` (standard commercial) and skips govcloud / CN partitions. A `DiscoveryWarning` is
emitted to the application notification stream.

### Azure AKS adapter — `AzureClusterDiscoveryAdapter`

Implemented in:
`ClusterConnectivity/Sources/Adapters/Azure/AzureClusterDiscoveryAdapter.swift`

Discovery calls (Azure Resource Manager REST API, authenticated with the MSAL token resolved by
`AzureExecCredentialAdapter`'s credential chain):

- `GET https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.ContainerService/managedClusters?api-version=2024-02-01`
  (paginated via `nextLink`). Required RBAC role: `Azure Kubernetes Service Cluster User Role`
  (read-only) or `Reader` on the subscription scope.

The adapter iterates `scopeHints.azureSubscriptionIds` if non-empty. Otherwise it first calls:

- `GET https://management.azure.com/subscriptions?api-version=2022-12-01`
  to enumerate accessible subscriptions.

CA certificate data is included in the `managedCluster.properties.agentPoolProfiles` response.
If the CA is absent (private cluster), the adapter emits a `DiscoveryWarning` and includes the
descriptor with an empty `caCertificatePEM`; the operator must supply the CA out-of-band.

### GCP GKE adapter — `GCPClusterDiscoveryAdapter`

Implemented in:
`ClusterConnectivity/Sources/Adapters/GCP/GCPClusterDiscoveryAdapter.swift`

Discovery calls (GKE API v1, authenticated with the ADC-derived access token resolved by
`GCPExecCredentialAdapter`'s credential chain):

- `GET https://container.googleapis.com/v1/projects/{project}/locations/{location}/clusters`
  (paginated). Required IAM permission: `container.clusters.list` on the project.

The adapter iterates `scopeHints.gcpProjects` if non-empty. Otherwise it calls the Resource
Manager API:

- `GET https://cloudresourcemanager.googleapis.com/v1/projects`
  to enumerate projects the authenticated principal can see. Required IAM permission:
  `resourcemanager.projects.get` (implicitly granted to any project member).

The adapter iterates `scopeHints.gcpLocations` if non-empty; otherwise it passes the literal
`-` as the location wildcard, which causes the GKE API to return clusters from all regions and
zones in a single paginated response (GKE API supports the `-` wildcard for locations).

## Credential acquisition rules

### AWS

The discovery adapter resolves credentials using the same soto 7.14.0 chain as
`AWSExecCredentialAdapter` (ADR-0018 section "AWS EKS authentication protocol"):

- environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`;
- `AWS_PROFILE` or `--profile` picker (see below);
- `~/.aws/credentials` and `~/.aws/config` (static credentials and named profiles);
- AssumeRole / AssumeRoleWithWebIdentity chaining (IRSA).

**Profile picker** — when `~/.aws/credentials` declares more than one profile, the welcome tab
shows a dropdown pre-populated with all named profiles. The operator selects the profile before
initiating discovery. The selection is passed as `scopeHints.awsProfile` (a string added to
`CloudScopeHints`; nil means use `AWS_PROFILE` or `[default]`).

**Region picker** — when `scopeHints.awsRegions` is empty and the operator has not set
`AWS_DEFAULT_REGION`, the welcome tab shows a multi-select region list defaulting to
`us-east-1`. The operator may add or remove regions before initiating discovery.

AWS SSO / IAM Identity Center profiles are handled by the subprocess fallback path described in
ADR-0018 (exec plugin with `aws-iam-authenticator`). Native SSO discovery is deferred.

### Azure

Credentials are resolved via MSAL (ADR-0018 section "Azure / AKS authentication protocol"):
device-code flow for interactive sign-in, service principal for non-interactive environments.

**Subscription picker** — when `scopeHints.azureSubscriptionIds` is empty and the enumerated
subscription list contains more than one entry, the welcome tab shows a multi-select picker listing
all subscription names and IDs. The operator may select a subset before initiating discovery.

The token scope for discovery is `https://management.azure.com/.default`. This is the same scope
used by `AzureExecCredentialAdapter`; no second MSAL authentication prompt is shown if a valid
token is already cached.

### GCP

Credentials are resolved via the ADC chain (ADR-0018 section "GCP / GKE authentication protocol"):
`GOOGLE_APPLICATION_CREDENTIALS` file, then `~/.config/gcloud/application_default_credentials.json`.

**Project picker** — when `scopeHints.gcpProjects` is empty and the enumerated project list
contains more than one entry, the welcome tab shows a multi-select picker listing all accessible
project IDs and display names.

The access token scope required for discovery is `https://www.googleapis.com/auth/cloud-platform`
(read-only suffices). The same token used by `GCPExecCredentialAdapter` may be reused if it has
not yet expired. The discovery adapter inspects the token's expiry timestamp before reuse and
refreshes proactively if fewer than 60 seconds remain.

## Kubeconfig materialisation rules

The `materialiseKubeconfig` operation on each provider adapter produces a `KubeconfigEntry` that
maps to a kubeconfig cluster + context + user triple. The exec block in the user entry is selected
to match the existing ADR-0018 adapter registry:

```
Provider   exec command            args
---------- ----------------------- ----------------------------------
AWS EKS    aws                     [eks, get-token, --cluster-name, <name>, --region, <region>]
Azure AKS  kubelogin               [get-token, --environment, AzurePublicCloud, ...]
GCP GKE    gke-gcloud-auth-plugin  []
```

These exec blocks are identical in structure to what `aws eks update-kubeconfig`,
`az aks get-credentials`, and `gcloud container clusters get-credentials` produce. Operators who
already have these clusters in a hand-managed kubeconfig file will see a merge conflict at the
context name level; the import sheet warns the operator and offers to rename the incoming context.

The cluster name in the kubeconfig context follows the provider naming convention:

- AWS: `arn:<partition>:eks:<region>:<account>:cluster/<name>` (ARN format, matching
  `aws eks update-kubeconfig` output).
- Azure: `<resourceGroupName>-<clusterName>` (matching `az aks get-credentials` output).
- GCP: `gke_<projectId>_<location>_<clusterName>` (matching `gcloud` output).

Using the cloud-native naming convention ensures that a kubeconfig produced by K8S-Manager is
merge-compatible with one produced by the cloud CLI.

## DigitalOcean DOKS deferred

DigitalOcean DOKS discovery (`doctl kubernetes cluster list`) is explicitly deferred. The gap
analysis (`feature-gap-analysis-lens-prism-ai.md`, item R12b) notes that the Lens recording
surfaces DOKS clusters under "Local Kubeconfigs" (not a dedicated provider section), indicating
that Lens does not implement native DOKS discovery either. A future ADR may opt DOKS discovery in
once DOKS clusters reach sufficient operator demand to justify the implementation cost.

## Followups

- Define `DiscoveryWarning` value type and the application notification stream contract (feeds
  ADR-0039 or a new notifications ADR).
- Specify the import-sheet UI for conflict detection and rename on context-name collision
  (interacts with ADR-0054 welcome tab).
- Decide whether to display discovered clusters in a preview list before committing import
  (prevents accidental bulk import).
- Evaluate whether `ec2:DescribeRegions` should be pre-checked and if not available, the UI
  should surface a one-click region picker instead of the static fallback.
- Track Google oauth2 token endpoint changes (google-auth-library-swift was archived; K8S-Manager
  owns this implementation path per ADR-0018).
- Revisit DOKS discovery when DigitalOcean Kubernetes adoption among K8S-Manager operators reaches
  a threshold that justifies implementation.

## Pros and cons of the options

### Option A — Per-provider native port adapters (chosen)

- Good, because subprocess-free; compatible with App Store distribution.
- Good, because incremental: each provider ships independently.
- Good, because credential chain is shared with ADR-0018 adapters.
- Bad, because three new API surfaces to maintain.
- Bad, because Azure private clusters require operator out-of-band CA supply.

### Option B — Cloud CLI invocation (subprocess)

- Good, because zero discovery logic to implement; delegate to mature CLIs.
- Bad, because contradicts ADR-0001 and ADR-0018 subprocess-free distribution goal.
- Bad, because operators must have aws, az, gcloud installed and on PATH.
- Bad, because exec PATH resolution is fragile under macOS Launch Agent environments.

### Option C — Unified cloud-abstraction library

- Good, because a single API surface for all three providers.
- Bad, because no Swift-native library exists at the required quality level; Pulumi Automation
  API targets Go/TypeScript; Crossplane targets Kubernetes-hosted infrastructure operators.
- Bad, because introduces a large indirect dependency with unknown Swift 6 compliance.
- Bad, because adds licensing constraints beyond the MIT/Apache-2.0 baseline used in ADR-0018.

## Confirmation

- Gherkin features under `docs/arch/contexts/cluster_connectivity/features/` cover the three
  provider discovery flows: `aws-cluster-discovery.feature`, `azure-cluster-discovery.feature`,
  `gcp-cluster-discovery.feature`. Each covers discovery happy path, missing-credentials error,
  scope-hint filtering, and partial-failure tolerance.
- `CloudClusterDiscoveryPort` contract tests assert that each adapter returns the same
  `ClusterDescriptor` shape for an equivalent cluster across providers.
- A security test asserts that the IAM/RBAC permissions requested by each adapter match the
  minimum set declared in this ADR (no broader scopes solicited).
- An integration test runs against `localstack`/Azurite/`pubsub-emulator`-style mocks to verify
  that the pagination handling for each provider's list endpoint terminates correctly.
- Kubeconfig materialisation produces entries that pass `kubectl --kubeconfig <generated>
  cluster-info` against a live cluster (smoke test, runs manually).

## More information

- ADR-0001 — No-subprocess distribution goal.
- ADR-0018 — Credential chain and adapter registry; exec block structure per provider.
- ADR-0051 — Provider grouping in the cluster strip sidebar (AKS, EKS, GKE, OIDC,
  Local Kubeconfigs sections).
- ADR-0054 — Welcome tab with five cluster-acquisition entry points (pending ratification).
- `feature-gap-analysis-lens-prism-ai.md` — items R12, R13, R12a (source of this ADR).
- Gherkin features — `cluster_connectivity/features/aws-cluster-discovery.feature`,
  `cluster_connectivity/features/azure-cluster-discovery.feature`,
  `cluster_connectivity/features/gcp-cluster-discovery.feature`.
