// DDD role: AggregateRoot
package helm_management

// #Release is the aggregate root of the helm_management bounded context.
// It represents a single named Helm release within a Kubernetes namespace,
// at a specific revision. A release aggregate is materialised by decoding
// a Kubernetes Secret of type "helm.sh/release.v1" that was written by
// the Helm 3 secret storage driver.
//
// The aggregate carries the full decoded state for one revision: chart
// metadata, user-supplied values, the rendered manifest YAML that was
// applied to the cluster, declared hooks, lifecycle info, and the name
// of the source Secret. Multiple #Release values with the same name and
// namespace but different version integers represent the revision history
// of a single logical Helm release. Grouping and history projection are
// the responsibility of ReleaseReaderActor (DomainService).
//
// SECURITY INVARIANT: #Release MUST NOT be materialised from a Secret that
// fails the release_decoder_invariants Rego policy. The ReleaseDecoderPort
// adapter is responsible for applying the policy before constructing this
// aggregate. A manifestYAML that contains PEM-encoded certificate material
// must cause the decoder to reject the Secret rather than surface it to
// the operator.
//
// Revision numbering starts at 1. Version is the Helm revision integer, not
// a semantic version string. Chart version is carried in chart.version.
#Release: {
	// id is a UUIDv7 generated deterministically from the combination of
	// kubernetesContextId, namespace, name, and version at decode time.
	// Stable across application restarts for the same revision Secret.
	id!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// kubernetesContextId is the UUIDv7 of the active cluster context
	// provided by cluster_connectivity at the time the release was decoded.
	kubernetesContextId!: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

	// name is the Helm release name. Sourced from the decoded release JSON,
	// not from the Secret name (to handle edge cases where the Secret name
	// and payload name diverge). Must conform to Helm's naming rules:
	// lowercase alphanumeric with dots and hyphens, 1 to 53 characters.
	name!: =~"^[a-z0-9]([a-z0-9.\\-]{0,51}[a-z0-9])?$"

	// namespace is the Kubernetes namespace in which this release was
	// deployed. Sourced from the decoded release JSON.
	namespace!: string

	// version is the Helm revision number for this release instance.
	// Starts at 1 for the initial install. Incremented by 1 on each
	// upgrade or rollback. Must be >= 1.
	version!: int & >=1

	// status is the Helm release status at the time this revision was
	// last written. The values mirror the Helm 3 release.Status type.
	//
	// - "deployed"         — the release was successfully applied.
	// - "uninstalled"      — the release was uninstalled (all resources deleted).
	// - "superseded"       — an older revision that has been replaced by a newer one.
	// - "failed"           — the install or upgrade did not complete successfully.
	// - "pending-install"  — install is in progress.
	// - "pending-upgrade"  — upgrade is in progress.
	// - "pending-rollback" — rollback is in progress.
	status!: "deployed" | "uninstalled" | "superseded" | "failed" |
		"pending-install" | "pending-upgrade" | "pending-rollback"

	// chart contains the metadata of the chart that was used to render
	// this release revision. See #ChartMetadata in chart_metadata.cue.
	chart!: #ChartMetadata

	// info contains lifecycle timestamps and the human-readable description
	// for this revision. See #ReleaseInfo in release_history_entry.cue.
	info!: #ReleaseInfo

	// manifestYAML is the full rendered manifest string that Helm applied
	// to the cluster for this revision. It is the concatenation of all
	// rendered template outputs separated by YAML document separators.
	// May be empty for releases that were installed with no templates.
	// Must not contain PEM-encoded certificate blocks (enforced by
	// release_decoder_invariants policy).
	manifestYAML!: string

	// valuesJSON is the JSON serialisation of the user-supplied values
	// (the "config" field in the Helm release JSON). An empty object
	// ("{}") represents an install with no value overrides.
	valuesJSON!: string

	// hooks is the list of Hook manifests declared by the chart.
	// Each hook carries its manifest YAML, the events that trigger it,
	// its delete policy, and its execution weight.
	hooks!: [...#HookManifest]

	// modifiedAtRFC3339 is the RFC3339 timestamp of the last-deployed
	// time for this specific revision. Sourced from info.lastDeployed.
	modifiedAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// sourceSecretName is the name of the Kubernetes Secret from which
	// this release aggregate was decoded. Follows the Helm naming
	// convention: "sh.helm.release.v1.<name>.v<version>".
	// Example: "sh.helm.release.v1.my-release.v3"
	sourceSecretName!: =~"^sh\\.helm\\.release\\.v1\\.[a-z0-9][a-z0-9.\\-]{0,51}\\.v[0-9]+$"
}
