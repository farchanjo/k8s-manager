// DDD role: AggregateRoot
// ADR: ADR-0057 — Bottom-docked terminal pane with node-debug shell integration
//
// Defines #DockedTerminalKind, #TerminalConnectionState, #DockedTerminalTab
// (ValueObject), and #DockedTerminalPaneState (AggregateRoot).
//
// `DockedTerminalPane` (Swift actor) owns #DockedTerminalPaneState at
// runtime. Persisted per workspace to:
//   ~/Library/Application Support/K8sManager/workspace/docked-terminal-pane.json
//
// The dedicated `TerminalSessionView` tab defined by ADR-0017 coexists with
// this pane; both are presentation surfaces over the same
// `TerminalSessionActor` transport layer. See ADR-0057 §Decision outcome.

package app_shell

import "strings"

// _dockedUUID is the canonical UUIDv7 pattern for DockedTerminalTab and pane
// identifiers.
_dockedUUID: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// _dockedRFC3339 validates RFC 3339 timestamps used in tab lifecycle fields.
_dockedRFC3339: string & =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"

// ---------------------------------------------------------------------------
// #DockedTerminalKind — closed set of session kinds hosted in the docked pane
// ---------------------------------------------------------------------------

// #DockedTerminalKind discriminates the kind of PTY session a docked tab
// hosts. Each kind maps to a distinct entry sequence in `TerminalSessionActor`
// and to distinct UI affordances (label format, connection banner text).
#DockedTerminalKind:
	"podExec" |        // Pod exec session opened from a Pod row or detail drawer
	"nodeDebug" |      // `kubectl debug node` session via ephemeral debug pod
	"containerExec"    // Ad-hoc container exec via the docked pane `+` button

// ---------------------------------------------------------------------------
// #TerminalConnectionState — lifecycle states for a docked tab
// ---------------------------------------------------------------------------

// #TerminalConnectionState mirrors the lifecycle states of the backing
// `TerminalSessionActor`. The docked pane uses this value to drive the
// per-tab indicator dot (green/amber/red) and the connection banner inside
// the PTY viewport.
//
// State transitions (always forward, except `error` which is terminal):
//   opening → open → closing → closed
//   opening → error
//   open    → error
#TerminalConnectionState:
	"opening" |   // Initial state; WebSocket handshake or debug pod creation in flight
	"open" |      // Live PTY; bidirectional I/O streaming
	"closing" |   // Operator requested close; final frames being flushed
	"closed" |    // Session ended cleanly; banner shows "Session closed" + Reopen
	"error"       // Session failed; banner shows error + Retry

// ---------------------------------------------------------------------------
// #DockedTerminalTab — ValueObject
// ---------------------------------------------------------------------------

// #DockedTerminalTab is one tab in the docked terminal pane tab bar.
// Each tab represents one `TerminalSessionActor` session. Tabs are persisted
// (without PTY output buffer per ADR-0017 §Decision drivers) to allow cold-
// launch restore in the closed state.
#DockedTerminalTab: {
	// id is a UUIDv7 uniquely identifying this docked tab instance.
	// Generated when the tab is opened; never reused.
	id: string & _dockedUUID

	// kind discriminates the session kind hosted by the tab.
	kind: #DockedTerminalKind

	// label is the human-readable string rendered in the tab bar
	// (e.g. "Node: worker-01", "Pod: api-server-abc12", "Container: nginx").
	// Max 64 characters; truncated with ellipsis in the tab bar UI.
	label: string & strings.MinRunes(1) & strings.MaxRunes(64)

	// clusterId identifies the cluster this session belongs to. Tabs whose
	// cluster has been unpinned from the strip (ADR-0051) MUST be closed,
	// not silently left orphaned. The `docked_terminal_policy.rego` policy
	// enforces this invariant.
	clusterId: string & _dockedUUID

	// targetNodeName is the Node name targeted by `kind: nodeDebug` sessions.
	// Required when kind == "nodeDebug"; absent otherwise.
	targetNodeName?: string & strings.MinRunes(1) & strings.MaxRunes(253)

	// targetPodNamespace is the namespace of the Pod targeted by
	// `kind: podExec` or `kind: containerExec` sessions.
	// Required when kind ∈ {"podExec", "containerExec"}; absent for nodeDebug.
	targetPodNamespace?: string & strings.MinRunes(1) & strings.MaxRunes(253)

	// targetPodName is the Pod name targeted by `kind: podExec` or
	// `kind: containerExec` sessions.
	// Required when kind ∈ {"podExec", "containerExec"}; absent for nodeDebug.
	targetPodName?: string & strings.MinRunes(1) & strings.MaxRunes(253)

	// targetContainerName is the container name within the target Pod.
	// Required when kind == "containerExec"; optional for "podExec" (defaults
	// to the Pod's first container at runtime); absent for "nodeDebug".
	targetContainerName?: string & strings.MinRunes(1) & strings.MaxRunes(253)

	// connectionState mirrors the backing `TerminalSessionActor` lifecycle.
	// On cold launch, persisted tabs are restored with connectionState
	// "closed" until the operator taps Reopen (ADR-0057 §Persistence).
	connectionState: #TerminalConnectionState

	// openedAt is the RFC 3339 timestamp when this tab was originally opened.
	// Preserved across restarts so the tab bar can sort by recency if needed.
	openedAt: _dockedRFC3339
}

// ---------------------------------------------------------------------------
// #DockedTerminalPaneState — AggregateRoot
// ---------------------------------------------------------------------------

// #DockedTerminalPaneState is the workspace-scoped aggregate persisted to
// `docked-terminal-pane.json`. Owned by `DockedTerminalPane` (Swift actor).
// Restored on cold launch; the pane slides up only if `tabs` is non-empty.
#DockedTerminalPaneState: {
	// schemaVersion enables forward-compatible migrations.
	schemaVersion: int & >=1
	schemaVersion: *1 | _

	// paneHeight is the current pane height in points. Persisted on every
	// resize. Default 33 % of content area height at first open; minimum
	// 120 pt; maximum 80 % of content area height. The policy enforces the
	// runtime bounds — schema enforces only the absolute floor.
	paneHeight: number & >=120

	// fullscreen indicates whether the operator has expanded the pane to
	// fill the content area. Persisted so cold launch restores the visual
	// state the operator left.
	fullscreen: bool
	fullscreen: *false | _

	// tabs is the ordered list of docked tabs (left-to-right).
	// Maximum cardinality enforced at runtime by `DockedTerminalPane` to
	// match the tab bar's overflow scroll behaviour.
	tabs: [...#DockedTerminalTab]

	// activeTabId is the id of the focused tab. Absent when `tabs` is empty.
	activeTabId?: string & _dockedUUID

	// lastPersistedAt is the RFC 3339 timestamp of the last successful write.
	lastPersistedAt: _dockedRFC3339
}

// ---------------------------------------------------------------------------
// Architecture invariants (documented; enforced by docked_terminal_policy.rego
// and DockedTerminalPane Swift actor)
// ---------------------------------------------------------------------------
//
// 1. tab.id MUST be unique across all tabs in `tabs`.
//
// 2. tab.kind == "nodeDebug" requires targetNodeName to be set; the policy
//    rejects tabs that violate this invariant.
//
// 3. At most one tab with kind == "nodeDebug" may exist per
//    (clusterId, targetNodeName) pair. Opening a duplicate brings the
//    existing tab to focus.
//
// 4. tab.clusterId MUST appear in the ClusterStripState.pins list. Tabs
//    whose cluster is unpinned are closed before strip persistence.
//
// 5. activeTabId, when set, MUST refer to a tab in `tabs`.
//
// 6. On cold launch, every restored tab has connectionState == "closed".
//    `TerminalSessionActor` is not auto-started; the operator must tap
//    Reopen on the per-tab banner.
//
// 7. paneHeight bounds: [120 pt, contentAreaHeight × 0.8]. The schema only
//    enforces the lower bound; the policy enforces the upper bound because
//    it depends on the live contentAreaHeight.
