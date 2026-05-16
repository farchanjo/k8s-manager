// DDD role: AggregateRoot
// ADR: ADR-0051 — Multi-cluster workspace: cluster strip, provider grouping, pinning, and chrome layout
//
// Defines #ClusterStripPin (ValueObject) and #ClusterStripState (AggregateRoot).
//
// The ClusterStripActor owns #ClusterStripState at runtime. Persisted to:
//   ~/Library/Application Support/K8sManager/workspace/cluster-strip-pins.json
//
// The workspace/ directory is global (not per-cluster). The strip is restored before
// cluster sessions are established so avatars are visible immediately on cold launch.

package app_shell

import "strings"

// _stripUUID is the canonical UUIDv7 pattern for ClusterStripPin identifiers.
_stripUUID: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// _stripRFC3339 validates RFC 3339 timestamps used in pin lifecycle fields.
_stripRFC3339: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

// ---------------------------------------------------------------------------
// #ProviderKind — enum of cluster provider authentication methods
// ---------------------------------------------------------------------------

// #ProviderKind classifies how the cluster's credentials are resolved.
// Used for provider section grouping in the sidebar tree (ADR-0051).
#ProviderKind:
	"aks" |    // Azure Kubernetes Service — Azure credential adapter
	"eks" |    // Elastic Kubernetes Service — AWS credential adapter
	"gke" |    // Google Kubernetes Engine — GCP credential adapter
	"oidc" |   // OIDC exec block — OIDC credential adapter
	"local"    // Static credential, client certificate, token, or unknown exec plugin

// ---------------------------------------------------------------------------
// #ClusterStripPin — ValueObject
// ---------------------------------------------------------------------------

// #ClusterStripPin represents one pinned cluster entry in the cluster strip.
// Each pin is a circular avatar chip displayed in the vertical strip at the
// left extreme of the main window.
#ClusterStripPin: {
	// clusterId uniquely identifies the cluster (shared_kernel.#ClusterId).
	// UUIDv7; stable across restarts.
	clusterId: string & _stripUUID

	// displayName is the human-readable cluster name shown in the avatar tooltip.
	// Derived from the kubeconfig context name. Max 128 characters.
	displayName: string & strings.MinRunes(1) & strings.MaxRunes(128)

	// initials is the 1–2 character label rendered inside the avatar circle.
	// Derived from displayName: first character of each word, up to 2 words.
	// e.g. "my-production" → "MP"; "local" → "LO".
	initials: string & =~"^[A-Z0-9]{1,2}$"

	// colorIndex is the deterministically-assigned avatar background color.
	// Computed as hash(clusterId) mod 8. Values 0–7 map to the 8-color palette
	// defined in the design token system (ADR-0021, ADR-0051).
	// Palette indices (token names): 0=kindAccentPod, 1=kindAccentDeploy,
	// 2=kindAccentService, 3=kindAccentStorage, 4=kindAccentConfig,
	// 5=kindAccentRBAC, 6=accentBrand, 7=statusWarning.
	colorIndex: int & >=0 & <=7

	// pinOrder is the zero-based position of this pin in the strip (top to bottom).
	// Invariant: pinOrder values across all pins in a ClusterStripState must be unique
	// and form a contiguous sequence starting at 0.
	pinOrder: int & >=0

	// isPinned must always be true for entries stored in ClusterStripState.tabs.
	// Kept as a field to allow future partial-pin states without schema breakage.
	isPinned: bool
	isPinned: *true | _

	// providerKind classifies the cluster's credential provider for sidebar grouping.
	providerKind: #ProviderKind

	// pinnedAt is the RFC 3339 timestamp when this cluster was pinned.
	pinnedAt: _stripRFC3339
}

// ---------------------------------------------------------------------------
// #ClusterStripState — AggregateRoot
// ---------------------------------------------------------------------------

// #ClusterStripState is the aggregate root persisted to cluster-strip-pins.json.
// Owned exclusively by ClusterStripActor. Restored on cold launch before any
// cluster session is established.
#ClusterStripState: {
	// schemaVersion enables forward-compatible migrations.
	// Starts at 1; incremented on breaking field changes.
	schemaVersion: int & >=1
	schemaVersion: *1 | _

	// pins is the ordered list of pinned cluster entries, top (index 0) to bottom.
	// Maximum 16 pins (practical limit; the strip height constrains the avatar count
	// at standard macOS window heights).
	// len(pins) <= 16 — invariant enforced at runtime by ClusterStripActor.
	pins: [...#ClusterStripPin]

	// lastPersistedAt is the RFC 3339 timestamp of the last successful write.
	lastPersistedAt: _stripRFC3339
}

// ---------------------------------------------------------------------------
// Architecture invariants (documented; enforced in ClusterStripActor)
// ---------------------------------------------------------------------------
//
// 1. pinOrder values across all pins MUST be unique and contiguous (0, 1, 2, …).
//    ClusterStripActor normalises the sequence after every reorder or remove operation.
//
// 2. colorIndex MUST equal hash(clusterId) mod 8. It is stored redundantly for
//    cold-launch rendering speed (avoids re-hashing on every frame).
//
// 3. initials MUST be derived deterministically from displayName at pin time.
//    If displayName changes, initials are recalculated on the next save.
//
// 4. A clusterId MUST NOT appear more than once in the pins list.
//
// 5. The strip persists on every mutation, atomic via write-to-tmp-then-rename.
//
// 6. isPinned is always true in persisted state. A cluster is either in the
//    strip (pinned) or not; there is no persisted "unpinned" state.
