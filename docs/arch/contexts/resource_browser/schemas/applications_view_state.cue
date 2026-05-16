// DDD role: AggregateRoot
// ADR: ADR-0067 — Applications cluster scope (Helm releases plus GitOps applications)
//
// Defines #ApplicationSource, #ApplicationsViewState (AggregateRoot), and
// #ApplicationRow (ReadModel) for the Applications sidebar entry.
//
// Option C (Helm-only v1) is the active configuration; argocdEnabled and
// fluxEnabled feature flags reserve future GitOps coverage without a
// schema-breaking change.

package resource_browser

import "strings"

// _appsRFC3339 validates RFC 3339 timestamps.
_appsRFC3339: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

// _appsUUID is the canonical UUIDv7 pattern.
_appsUUID: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// ---------------------------------------------------------------------------
// #ApplicationSource — closed enum of aggregation sources
// ---------------------------------------------------------------------------

// #ApplicationSource discriminates which underlying data source produced
// an `ApplicationRow`. Currently only `helmReleases` is wired in v1; the
// remaining sources are reserved for follow-up ADRs gated by CRD discovery
// (ADR-0052) and the corresponding feature flag on `#ApplicationsViewState`.
#ApplicationSource:
	"helmReleases" |           // Decoded from `helm.sh/release.v1` Secrets (ADR-0015)
	"argocdApplications" |     // From `argoproj.io/v1alpha1/Application` (deferred)
	"argocdApplicationSets" |  // From `argoproj.io/v1alpha1/ApplicationSet` (deferred)
	"fluxKustomizations"       // From `kustomize.toolkit.fluxcd.io/v1/Kustomization` (deferred)

// ---------------------------------------------------------------------------
// #HelmReleaseStatus — closed set of Helm release statuses
// ---------------------------------------------------------------------------

// #HelmReleaseStatus mirrors the `info.status` enum from Helm's release
// metadata. Maps to a `StatusChip` variant via the row renderer.
#HelmReleaseStatus:
	"deployed" |          // Success terminal state
	"failed" |            // Failed terminal state
	"pending-install" |   // Transient
	"pending-upgrade" |   // Transient
	"pending-rollback" |  // Transient
	"uninstalled" |       // Terminal (release removed but secret retained)
	"superseded"          // Earlier revision replaced by a newer revision

// ---------------------------------------------------------------------------
// #ApplicationRow — ReadModel
// ---------------------------------------------------------------------------

// #ApplicationRow is a single row rendered in the `ApplicationsView` list.
// In v1 every row carries source == "helmReleases" and is sourced from the
// `HelmManagement` actor's read model.
#ApplicationRow: {
	// rowId is a stable identifier for the row across reloads. For Helm
	// releases the rowId is computed as `helm:<namespace>/<name>:<revision>`.
	rowId: string & strings.MinRunes(1)

	// source identifies which aggregation source produced this row.
	source: #ApplicationSource

	// name is the application/release name (e.g. Helm release name).
	name: string & strings.MinRunes(1) & strings.MaxRunes(253)

	// chart is the chart name without repository prefix (e.g. "nginx-ingress").
	// Only meaningful for source == "helmReleases".
	chart?: string & strings.MinRunes(1) & strings.MaxRunes(253)

	// version is the chart version string (e.g. "4.10.0") for Helm rows or
	// the targetRevision for GitOps rows.
	version: string & strings.MinRunes(1) & strings.MaxRunes(64)

	// status is the rendered application status. The enum is Helm-shaped in
	// v1; GitOps sources will surface their own status enum via this field
	// when ratified by follow-up ADRs.
	status: #HelmReleaseStatus

	// updated is the RFC 3339 timestamp of the last deployment / sync event.
	// Rendered as a relative duration ("3 days ago") in the row UI.
	updated: _appsRFC3339

	// namespace is the namespace where the application is deployed.
	namespace: string & strings.MinRunes(1) & strings.MaxRunes(253)

	// revision is the current revision integer.
	// For Helm: the release revision counter.
	// For GitOps: the operator-visible revision number (commit SHA short form).
	revision: int & >=1
}

// ---------------------------------------------------------------------------
// #ApplicationsViewState — AggregateRoot
// ---------------------------------------------------------------------------

// #ApplicationsViewState is the per-cluster view-model state for the
// Applications sidebar entry. Persisted alongside the `OpenTabsState` for
// tab restoration; held in memory by `ApplicationsViewModel`.
#ApplicationsViewState: {
	// schemaVersion enables forward-compatible migrations.
	schemaVersion: int & >=1
	schemaVersion: *1 | _

	// clusterId identifies which cluster this state belongs to.
	clusterId: string & _appsUUID

	// rows is the current projection of Applications visible to the operator
	// after the global namespace filter (ADR-0053) is applied.
	rows: [...#ApplicationRow]

	// activeNamespaceFilter mirrors the global namespace filter at the
	// moment the rows projection was last computed. Empty string means
	// "All Namespaces".
	activeNamespaceFilter: string

	// sortColumn identifies which column is currently sorting the rows.
	// Default "name" ascending; the operator may change the sort.
	sortColumn: "name" | "chart" | "version" | "status" | "updated" |
		"namespace" | "revision"
	sortColumn: *"name" | _

	// sortAscending indicates the sort direction.
	sortAscending: bool
	sortAscending: *true | _

	// argocdEnabled is the feature flag controlling whether the
	// `argocdApplications` and `argocdApplicationSets` sources are queried.
	// Default false. Setting true is gated by CRD discovery (ADR-0052) and
	// by the `applications_view_policy.rego` policy. v1 always sees false.
	argocdEnabled: bool
	argocdEnabled: *false | _

	// fluxEnabled is the feature flag controlling whether the
	// `fluxKustomizations` source is queried. Default false; same gating as
	// argocdEnabled. v1 always sees false.
	fluxEnabled: bool
	fluxEnabled: *false | _

	// lastRefreshedAt is the RFC 3339 timestamp of the last successful
	// refresh of `rows` from the `HelmManagement` read model.
	lastRefreshedAt: _appsRFC3339
}

// ---------------------------------------------------------------------------
// Architecture invariants (documented; enforced by applications_view_policy.rego
// and the ApplicationsViewModel)
// ---------------------------------------------------------------------------
//
// 1. In v1, every row.source MUST equal "helmReleases". Rows with other
//    sources require the corresponding feature flag to be true AND the
//    matching CRD group to be discovered by ADR-0052.
//
// 2. argocdEnabled implies the `argoproj.io` CRD group must be present in
//    the discoveredCRDGroups list.
//
// 3. fluxEnabled implies the `kustomize.toolkit.fluxcd.io` CRD group must
//    be present in the discoveredCRDGroups list.
//
// 4. rows is filtered by activeNamespaceFilter before being persisted; an
//    empty filter means no namespace restriction.
//
// 5. Helm releases in status == "superseded" are excluded from rows by
//    default (matching ADR-0015 Phase 1 behaviour).
