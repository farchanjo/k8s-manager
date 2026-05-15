// DDD role: AggregateRoot
// Domain: resource_browser
// Aggregate: EditorSession — represents a single interactive session in the
// integrated multi-format editor (MD / YAML / JSON).
// See: docs/arch/decisions/adr-0030-integrated-editor-md-yaml-json.md

package resource_browser

import "strings"

// UUIDv7 regex per project convention.
#UUIDv7: =~"^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"

// RFC3339 timestamp (UTC).
#RFC3339: =~"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?Z$"

// ---------------------------------------------------------------------------
// Supporting value objects
// ---------------------------------------------------------------------------

// #ResourceRef identifies the Kubernetes resource being edited.
// Set to null for Markdown-only editor sessions (e.g., standalone README).
#ResourceRef: {
	// API version string, e.g. "apps/v1" or "v1".
	apiVersion: string & strings.MinRunes(1)

	// Kubernetes kind name, e.g. "Deployment", "ConfigMap".
	kind: string & strings.MinRunes(1)

	// Namespace of the resource. Null for cluster-scoped resources.
	namespace?: string | null

	// Name of the resource instance.
	name: string & strings.MinRunes(1)
}

// #Diagnostic represents a single validation finding within the editor.
// Produced by RealtimeValidatorService and K8sSchemaValidator.
#Diagnostic: {
	// Severity of the finding.
	severity: "error" | "warning" | "info"

	// 1-based line number within the document.
	lineNumber: int & >=1

	// 1-based column number. Optional — may be absent when the source
	// does not provide column-level precision.
	columnNumber?: int & >=1

	// Human-readable description of the finding.
	message: string & strings.MinRunes(1)

	// Service that produced this diagnostic.
	source: "yaml-parser" | "json-parser" | "k8s-schema" | "json-schema" | "linter"
}

// #FieldConflict describes a server-side apply field ownership conflict
// returned by the Kubernetes API server (HTTP 409).
#FieldConflict: {
	// JSON Pointer path to the conflicting field (e.g. "/spec/replicas").
	fieldPath: string & strings.MinRunes(1)

	// Field manager that currently owns this field on the server.
	currentManager: string & strings.MinRunes(1)

	// Field manager attempting to take ownership.
	// Fixed to the K8sManager field manager identifier by convention.
	attemptingManager: string & (strings.MinRunes(1)) | *"com.archanjo.K8sManager"
}

// ---------------------------------------------------------------------------
// EditorState sum type
// ---------------------------------------------------------------------------

// #StateIdle — editor is open in read-only mode. No editing has started.
#StateIdle: {
	type: "idle"
}

// #StateLoading — editor is fetching the resource manifest from the cluster.
#StateLoading: {
	type: "loading"
}

// #StateEditing — operator is actively editing the document. Validation
// diagnostics are continuously updated by RealtimeValidatorService.
#StateEditing: {
	type: "editing"

	// Current set of diagnostics (may be empty when document is valid).
	diagnostics: [...#Diagnostic]
}

// #StateValidating — a validation pass is in progress (100 ms debounce).
// Transitional state between keystroke and next #StateEditing.
#StateValidating: {
	type: "validating"

	// Diagnostics from the previous pass (shown during the current pass).
	diagnostics: [...#Diagnostic]
}

// #StateDryRunning — a server-side dry-run apply PATCH is in-flight.
#StateDryRunning: {
	type: "dryRunning"
}

// #StateDryRunComplete — the dry-run response has been received.
// The diff preview and any field conflicts are available.
#StateDryRunComplete: {
	type: "dryRunComplete"

	// Structured diff between the current server state and the proposed
	// manifest. Formatted as a unified diff string for display in the
	// diff preview pane.
	diffPreview: string

	// Field ownership conflicts returned by the API server (HTTP 409).
	// Empty when no conflicts were detected.
	conflicts: [...#FieldConflict]
}

// #StateApplying — the apply PATCH is in-flight (operator confirmed).
#StateApplying: {
	type: "applying"
}

// #StateApplied — the apply operation completed (success or failure).
#StateApplied: {
	type: "applied"

	// Outcome of the apply operation.
	outcome: "succeeded" | "failed"

	// Human-readable detail for the operator. Must not contain credential
	// material or raw Kubernetes API token values.
	outcomeDetail: string
}

// #StateError — a non-recoverable error occurred (load failure, network
// error, unexpected API response). The operator can dismiss and return
// to idle or editing.
#StateError: {
	type: "error"

	// Human-readable description of the error.
	errorDetail: string & strings.MinRunes(1)
}

// #EditorState is the discriminated union of all possible editor states.
#EditorState:
	#StateIdle |
	#StateLoading |
	#StateEditing |
	#StateValidating |
	#StateDryRunning |
	#StateDryRunComplete |
	#StateApplying |
	#StateApplied |
	#StateError

// ---------------------------------------------------------------------------
// EditorSession aggregate root
// ---------------------------------------------------------------------------

// #EditorSession is the AggregateRoot for the integrated editor. One instance
// is created per editor invocation. It is held in memory for the duration of
// the editing session and is discarded when the editor is closed.
//
// Persistence: #Draft (a separate Entity) snapshots dirty content to SQLite
// for crash recovery. #EditorSession itself is not stored in the database.
#EditorSession: {
	// Unique identifier for this editing session. UUIDv7.
	id: #UUIDv7

	// The active Kubernetes context at the time the session was opened.
	kubernetesContextId: #UUIDv7

	// Reference to the Kubernetes resource being edited.
	// Null for standalone Markdown sessions (no cluster resource backing).
	resourceRef?: #ResourceRef | null

	// Format of the content being edited.
	sourceFormat: "yaml" | "json" | "markdown"

	// Current content in the editor buffer (mutable during editing).
	currentContent: string

	// Original content as fetched from the cluster (or initial value).
	// Immutable after session creation.
	originalContent: string

	// Computed: true when currentContent differs from originalContent.
	// The application layer MUST compute this value; it is not stored.
	isDirty: bool

	// Current state of the editor session state machine.
	state: #EditorState

	// RFC3339 timestamp when the session was opened.
	openedAt: #RFC3339

	// RFC3339 timestamp of the last content modification.
	lastModifiedAt: #RFC3339

	// RFC3339 timestamp of the last diagnostics run. Absent before the
	// first validation pass completes.
	lastDiagnosticsRunAt?: #RFC3339

	// Debounce interval in milliseconds applied to:
	// - Validation runs (100 ms hard-coded in service; this value drives
	//   the dry-run debounce).
	// - Dry-run PATCH requests (YAML/JSON only).
	// Default: 500 ms.
	debounceMs: int & >=50 & <=5000 | *500
}
