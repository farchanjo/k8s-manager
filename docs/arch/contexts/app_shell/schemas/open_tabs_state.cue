// DDD role: AggregateRoot
// ADR: ADR-0050 — Resource navigation taxonomy: 51 standard Kubernetes kinds, CRD discovery,
//                  and multi-document tab system
//
// Defines #DocumentTab (ValueObject), #OpenTabsState (AggregateRoot), and #TabKind (enum).
//
// The OpenTabsActor owns #OpenTabsState at runtime. Persisted per cluster to:
//   ~/Library/Application Support/K8sManager/clusters/<clusterId>/open-tabs.json
//
// Tab identity is the tuple (clusterId, tabKind, namespace, kindName, resourceName).
// Tabs are UUIDv7-identified to support audit logging.

package app_shell

import "strings"

// _tabUUID is the canonical UUIDv7 pattern (local alias to avoid import clash).
_tabUUID: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// _tabRFC3339 validates RFC 3339 timestamps used in tab lifecycle fields.
_tabRFC3339: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

// ---------------------------------------------------------------------------
// #TabKind — enum of all document tab types
// ---------------------------------------------------------------------------

// #TabKind discriminates the purpose and rendering strategy of a DocumentTab.
#TabKind:
	"resourceList" |     // List view for a Kubernetes kind + namespace
	"resourceDetail" |   // Detail view for a named resource
	"clusterOverview" |  // Synthetic cluster overview (not a Kubernetes resource)
	"helmReleases" |     // Helm release list for a cluster
	"helmDetail" |       // Helm release detail
	"events" |           // Event feed for a cluster or namespace
	"terminalSession"    // Pod exec or Node debug terminal

// ---------------------------------------------------------------------------
// #DocumentTab — ValueObject
// ---------------------------------------------------------------------------

// #DocumentTab represents a single open tab in the multi-document tab bar.
// Tabs are owned by OpenTabsActor. Each tab carries enough context to
// re-establish its watch stream after a cold launch.
#DocumentTab: {
	// tabId is a UUIDv7 uniquely identifying this tab instance.
	// Generated when the tab is created; never reused.
	tabId: string & _tabUUID

	// clusterId identifies the cluster this tab belongs to.
	// UUIDv7 assigned at first kubeconfig parse (shared_kernel.#ClusterId).
	clusterId: string & _tabUUID

	// tabKind determines which view is rendered in the tab content area.
	tabKind: #TabKind

	// namespace is the Kubernetes namespace context for this tab.
	// Required for namespaced resourceList and resourceDetail tabs.
	// Absent for cluster-scoped tabs (clusterOverview, helmReleases, events).
	namespace?: string & strings.MinRunes(1)

	// kindName is the Kubernetes resource kind for resourceList and resourceDetail tabs.
	// e.g. "Deployment", "Pod", "ConfigMap".
	// Absent for clusterOverview, helmReleases, events, terminalSession.
	kindName?: string & strings.MinRunes(1)

	// resourceName is the name of the specific resource for resourceDetail tabs.
	// Absent for resourceList, clusterOverview, helmReleases, events.
	resourceName?: string & strings.MinRunes(1)

	// apiGroup is the Kubernetes API group for the kind (e.g. "apps", "batch").
	// Required for resourceList and resourceDetail tabs. Absent for synthetic tabs.
	apiGroup?: string

	// apiVersion is the Kubernetes API version string (e.g. "v1", "apps/v1").
	// Required for resourceList and resourceDetail tabs. Absent for synthetic tabs.
	apiVersion?: string & strings.MinRunes(1)

	// selectedVersion is the operator-selected CRD version for multi-version CRDs.
	// Absent for standard (compile-time) kinds.
	selectedVersion?: string & strings.MinRunes(1)

	// openedAt is the RFC 3339 timestamp when this tab was opened.
	openedAt: _tabRFC3339

	// isPinned indicates whether the tab is pinned.
	// Pinned tabs cannot be closed via the close button; they must be unpinned first.
	// Pinned tabs are not subject to LRU eviction.
	isPinned: bool
	isPinned: *false | _

	// scrollPosition is an opaque blob storing the scroll offset of the list or
	// detail view at the time the tab was last persisted. Restored on tab focus.
	// Value is base64-encoded JSON; nil if no scroll state has been captured yet.
	scrollPosition?: string

	// drawerWidth is the persisted width of the detail drawer for this tab's kind.
	// Range: 280–600 pt. Default: 360 pt.
	drawerWidth?: int & >=280 & <=600
}

// ---------------------------------------------------------------------------
// #OpenTabsState — AggregateRoot
// ---------------------------------------------------------------------------

// #OpenTabsState is the aggregate root persisted to open-tabs.json per cluster.
// Owned exclusively by OpenTabsActor. Restored on cold launch.
#OpenTabsState: {
	// clusterId identifies which cluster this tab state belongs to.
	clusterId: string & _tabUUID

	// schemaVersion enables forward-compatible migrations.
	// Starts at 1; incremented on breaking field changes.
	schemaVersion: int & >=1
	schemaVersion: *1 | _

	// tabs is the ordered list of open tabs, from left (index 0) to right.
	// Maximum 20 entries per cluster (enforced by OpenTabsActor in Swift).
	// len(tabs) <= 20 — invariant enforced at runtime, not expressible as CUE list bound.
	tabs: [...#DocumentTab]

	// activeTabId is the tabId of the currently focused tab.
	// May be absent if all tabs are closed.
	activeTabId?: string & _tabUUID

	// lastPersistedAt is the RFC 3339 timestamp of the last successful write.
	lastPersistedAt: _tabRFC3339
}

// ---------------------------------------------------------------------------
// Architecture invariants (documented; enforced in OpenTabsActor)
// ---------------------------------------------------------------------------
//
// 1. Only one tab may exist per (clusterId, tabKind, namespace, kindName, resourceName) tuple.
//    If a duplicate is opened, the existing tab is brought to focus instead.
//
// 2. isPinned == true tabs are exempt from LRU eviction and from the close button.
//
// 3. A resourceList or resourceDetail tab MUST have both kindName and apiVersion populated.
//
// 4. activeTabId, if set, MUST refer to a tabId present in the tabs list.
//
// 5. Tab persistence (write to open-tabs.json) is debounced to 500 ms to
//    avoid write storms during rapid tab operations.
//
// 6. On cold launch, resourceDetail tabs are restored only after the cluster
//    session is available. resourceList tabs are restored immediately.
//
// 7. If the cluster session for a tab is unavailable (e.g. cluster removed),
//    the tab is removed from the state on next successful load, not silently
//    kept with a stale state.
