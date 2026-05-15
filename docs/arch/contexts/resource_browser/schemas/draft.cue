// DDD role: Entity
// Domain: resource_browser
// Entity: Draft — a snapshot of a dirty editor session persisted to local
// SQLite storage for crash recovery and cross-session draft resumption.
//
// Persistence: editor_drafts table in local_persistence (storage.dbml).
// Schema migration added per ADR-0030.
// See: docs/arch/decisions/adr-0030-integrated-editor-md-yaml-json.md

package resource_browser

// ---------------------------------------------------------------------------
// #Draft entity
// ---------------------------------------------------------------------------

// #Draft represents a point-in-time snapshot of a dirty #EditorSession.
// DraftAutoSaver writes a new or updated #Draft row every 5 seconds while
// isDirty == true. On editor close without apply, the most-recent #Draft
// for the session is retained in the database. Rows older than 24 hours
// without a corresponding active session are eligible for pruning.
#Draft: {
	// Unique identifier for this draft row. UUIDv7.
	id: #UUIDv7

	// The editor session that produced this draft. Correlates with
	// #EditorSession.id. Used to group drafts by session and to offer
	// draft restoration on next open.
	editorSessionId: #UUIDv7

	// Reference to the Kubernetes resource whose manifest was being
	// edited. Null for standalone Markdown sessions.
	resourceRef?: #ResourceRef | null

	// Format of the content snapshot.
	sourceFormat: "yaml" | "json" | "markdown"

	// Full content of the editor buffer at the time of the snapshot.
	// When resourceRef.kind is "Secret" — or any kind whose discovered
	// OpenAPI v3 schema declares a `data` or `stringData` field —
	// DraftAutoSaver MUST replace every value in those maps with the
	// literal string "[REDACTED]" before serialising the buffer to this
	// field. The map keys are preserved; only the values are elided.
	// For all other kinds the content is stored verbatim. This
	// obligation is enforced by DraftAutoSaver and asserted by a
	// negative integration test that scans editor_drafts rows for known
	// Secret marker bytes.
	content: string

	// True when the Secret-redaction path was applied to `content`
	// before persistence. Set by DraftAutoSaver when the resource kind
	// (or its discovered OpenAPI v3 schema) contains a `data` or
	// `stringData` field. False for Markdown sessions, non-Secret
	// resources, and any draft predating the redaction obligation.
	sensitiveContentRedacted: bool | *false

	// RFC3339 timestamp when this snapshot was persisted.
	savedAt: #RFC3339

	// True when the draft was written automatically by DraftAutoSaver
	// (5-second debounce). False when the operator explicitly chose
	// "Save draft" from the editor menu.
	autoSaved: bool | *true
}
