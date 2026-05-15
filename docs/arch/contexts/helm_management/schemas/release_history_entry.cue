// DDD role: Entity
package helm_management

// #ReleaseHistoryEntry is an entity that represents a single row in the
// revision history of a Helm release. A history entry is derived from a
// #Release aggregate but carries only the fields needed for the history
// list view. Entries are ordered by revision integer (ascending) within
// the scope of a single (name, namespace) release identity.
//
// Unlike #Release (which is the full decoded aggregate), #ReleaseHistoryEntry
// is a projection used by the ReleaseListReadModel and ReleaseDetailReadModel
// when rendering the history panel. It does not carry the full manifest YAML
// or values to keep the read model payload small.
//
// Identity: (kubernetesContextId, namespace, name, revision). Two entries
// with the same identity represent the same Helm revision and must be
// deduplicated by the ReleaseReaderActor.
#ReleaseHistoryEntry: {
	// revision is the Helm revision number for this entry. Starts at 1.
	// Must match the "version" field of the corresponding #Release aggregate.
	revision!: int & >=1

	// deployedAtRFC3339 is the RFC3339 timestamp at which this revision
	// was last deployed. Sourced from info.lastDeployed of the corresponding
	// #Release.
	deployedAtRFC3339!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// status is the Helm status for this revision at the time it was last
	// written. Mirrors the status field of #Release.
	status!: "deployed" | "uninstalled" | "superseded" | "failed" |
		"pending-install" | "pending-upgrade" | "pending-rollback"

	// chartVersion is the semantic version string of the chart used for
	// this revision. Sourced from chart.version of the corresponding #Release.
	chartVersion!: =~"^[0-9]+\\.[0-9]+\\.[0-9]"

	// appVersion is the application version string from the chart. Optional;
	// not present for library charts or charts that omit the field.
	appVersion?: string

	// description is the Helm-generated human-readable notes for this
	// revision. Helm sets this to the chart's NOTES.txt output on install
	// and upgrade, and to "Rollback to <revision>" on rollback operations.
	description!: string

	// supersededAtRFC3339 is the RFC3339 timestamp at which this revision
	// was marked superseded by a newer revision. Absent for the current
	// (latest) revision.
	supersededAtRFC3339?: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
}

// #ReleaseInfo is a value object that carries the lifecycle timestamps
// and textual metadata for a single Helm release revision. It corresponds
// to the "info" field in the Helm release JSON.
//
// DDD role: ValueObject (nested within #Release).
#ReleaseInfo: {
	// firstDeployed is the RFC3339 timestamp of the first successful
	// installation of this release (revision 1). Sourced from info.first_deployed.
	firstDeployed!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// lastDeployed is the RFC3339 timestamp of the most recent successful
	// deployment of this revision. Sourced from info.last_deployed.
	lastDeployed!: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// deleted is the RFC3339 timestamp at which the release was uninstalled.
	// Present only for revisions with status "uninstalled".
	deleted?: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"

	// description is the human-readable status description. On install and
	// upgrade this is the rendered NOTES.txt. On rollback it is set to
	// "Rollback to <target revision>". On uninstall it is "Uninstallation complete".
	description!: string

	// status mirrors the release status at the time this info was written.
	status!: "deployed" | "uninstalled" | "superseded" | "failed" |
		"pending-install" | "pending-upgrade" | "pending-rollback"

	// notes is the raw NOTES.txt content rendered for this revision.
	// May be empty if the chart has no NOTES.txt template.
	notes!: string
}

// #HookManifest is a value object that describes a single Helm hook declared
// by the chart. Hooks are Kubernetes resource manifests that Helm applies
// at specific lifecycle events (pre-install, post-upgrade, etc.) rather
// than as part of the normal resource reconciliation.
//
// DDD role: ValueObject (nested within #Release).
//
// In Phase 1, hooks are read-only: K8sManager displays declared hooks and
// their execution metadata but does not invoke or re-apply them. Hook
// execution is the responsibility of the Helm CLI during install/upgrade.
#HookManifest: {
	// name is the hook's name, derived from the resource metadata.name
	// in the hook manifest.
	name!: string

	// kind is the Kubernetes resource kind of the hook resource.
	// Common examples: "Job", "Pod", "ServiceAccount".
	kind!: string

	// apiVersion is the API version string of the hook resource.
	// Example: "batch/v1", "v1".
	apiVersion!: string

	// events is the list of Helm lifecycle events that trigger this hook.
	// At least one event must be present. The closed set mirrors the Helm 3
	// hook annotation values.
	events!: [..."pre-install" | "post-install" | "pre-upgrade" | "post-upgrade" |
		"pre-delete" | "post-delete" | "pre-rollback" | "post-rollback" | "test"]

	// deletePolicy is the list of delete-policy annotations on this hook.
	// Governs when Helm deletes the hook resource after it completes.
	// Common values: "before-hook-creation", "hook-succeeded", "hook-failed".
	deletePolicy!: [...string]

	// weight is the hook's execution weight. Hooks are executed in
	// ascending order of weight. Negative weights are permitted.
	weight!: int
}
