// DDD Role: ValueObject
// Bounded context: local_persistence
// Described by: ADR-0026 (state persistence and filesystem layout)
//
// This file defines the value objects used during K8sManager's cold-launch
// restoration sequence. The RestorationManifest is assembled from
// storage.sqlite3 plus per-cluster JSON files under
// ~/.config/k8smanager/clusters/<clusterId>/. It drives the boot
// sequence described in ADR-0026 without coupling the bootstrap code to
// raw SQL or JSON parsing at the call site.

package local_persistence

// #UUIDv7 matches a canonical UUIDv7 string.
#UUIDv7: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// #RFC3339 is a non-empty string conforming to RFC 3339 timestamp format.
#RFC3339: string & !=""

// #LayoutOverrideJson is an opaque JSON string containing a serialised
// dashboard layout override. The schema of this JSON is owned by the
// analytics_dashboard bounded context; local_persistence stores it
// without interpreting it.
#LayoutOverrideJson: string & !=""

// #RestorationManifest is assembled once during cold launch by the
// PersistenceActor from storage.sqlite3 and per-cluster JSON files.
// It is handed off to the application bootstrap sequence and then
// discarded — it is not persisted anywhere as a whole document.
//
// DDD Role: ValueObject
// Assembled by: PersistenceActor (local_persistence domain service)
// Consumed by: Application bootstrap (top-level Swift entry point)
#RestorationManifest: {
	// schemaVersion is the version of this manifest format.
	// Increment when fields are added or removed so that the
	// bootstrap code can handle forward and backward compatibility.
	schemaVersion: int & >=1

	// lastClosedAt is the RFC 3339 timestamp recorded when the
	// application last performed a graceful shutdown. Absent on
	// fresh install or after a crash. Used for display ("last used
	// N hours ago") and for stale-data heuristics.
	lastClosedAt?: #RFC3339

	// activeContextId is the UUIDv7 of the ContextNavigationState
	// context that was active when the application last closed.
	// Absent on fresh install.
	activeContextId?: #UUIDv7

	// openTerminalSessions is the list of terminal-session UUIDv7
	// identifiers that were open at last shutdown. If non-empty, the
	// bootstrap sequence emits a RestorationPrompt of kind
	// "reopen_terminals" before spawning any terminal session.
	openTerminalSessions: [...#UUIDv7] | *[]

	// openPortForwards is the list of port-forward UUIDv7 identifiers
	// that were active at last shutdown. If non-empty, the bootstrap
	// sequence emits a RestorationPrompt of kind
	// "reopen_port_forwards" before re-establishing any listener.
	openPortForwards: [...#UUIDv7] | *[]

	// pinnedClusterContextIds is the ordered list of cluster context
	// UUIDv7 identifiers that the operator has pinned in the sidebar.
	// These sessions are spawned unconditionally on cold launch
	// without a prompt.
	pinnedClusterContextIds: [...#UUIDv7] | *[]

	// chatSessions is the list of chat-session UUIDv7 identifiers
	// that were open in the chat panel at last shutdown. Restored
	// in the order listed without prompting.
	chatSessions: [...#UUIDv7] | *[]

	// dashboardCustomLayouts is a map from a layout scope identifier
	// (typically a cluster context UUIDv7 or the literal "global")
	// to an opaque JSON string encoding the operator's dashboard
	// layout override for that scope.
	dashboardCustomLayouts: {
		[scope=string]: #LayoutOverrideJson
	}
}

// #RestorationPromptKind is the discriminator for operator-facing
// confirmation dialogs during cold-launch restoration.
#RestorationPromptKind:
	"reopen_terminals" |
	"reopen_port_forwards" |
	"migrate_storage_path"

// #RestorationPrompt represents a single operator-facing confirmation
// dialog that the bootstrap sequence may present during cold launch.
// Each prompt is persisted to storage.sqlite3 after the operator
// responds, providing an audit trail of restoration decisions.
//
// DDD Role: ValueObject
// Persisted by: PersistenceActor (local_persistence domain service)
// Presented by: Application bootstrap (top-level Swift entry point)
#RestorationPrompt: {
	// kind identifies the category of confirmation being requested.
	// "reopen_terminals" — asks the operator whether to reopen N
	//   terminal sessions from the previous application run.
	// "reopen_port_forwards" — asks the operator whether to reopen M
	//   port-forward listeners from the previous application run.
	// "migrate_storage_path" — asks the operator whether to move the
	//   legacy storage.sqlite3 from
	//   ~/Library/Application Support/com.archanjo.K8sManager/
	//   to ~/.config/k8smanager/ (ADR-0026 first-run migration).
	kind: #RestorationPromptKind

	// payload is an opaque JSON string carrying kind-specific
	// supplementary data needed to render the prompt.
	// For "reopen_terminals": {"count": N, "sessionIds": [...]}
	// For "reopen_port_forwards": {"count": M, "forwardIds": [...]}
	// For "migrate_storage_path": {"sourcePath": "...", "targetPath": "..."}
	payload: string & !=""

	// accepted records whether the operator confirmed (true) or
	// declined (false) the prompt. Set after operator interaction.
	accepted: bool

	// presentedAt is the RFC 3339 timestamp when the prompt was
	// displayed to the operator.
	presentedAt: #RFC3339
}
