// Domain/Draft.swift — resource_browser bounded context
// DDD role: Entity
// CUE source: docs/arch/contexts/resource_browser/schemas/draft.cue
// ADR ref: ADR-0030 (integrated editor MD / YAML / JSON)

import Foundation

// MARK: - Draft

/// Point-in-time snapshot of a dirty `EditorSession` persisted to local SQLite.
///
/// `DraftAutoSaver` writes a new or updated `Draft` row every 5 seconds while
/// `isDirty == true`. On editor close without apply, the most-recent `Draft`
/// for the session is retained in the database. Rows older than 24 hours
/// without a corresponding active session are eligible for pruning.
///
/// SECURITY INVARIANT: When `resourceRef.kind` is `"Secret"` — or any kind
/// whose OpenAPI v3 schema declares a `data` or `stringData` field —
/// `DraftAutoSaver` MUST replace every value in those maps with the literal
/// string `"[REDACTED]"` before serialising the buffer. The map keys are
/// preserved. This obligation is enforced by `DraftAutoSaver` and asserted by a
/// negative integration test.
///
/// Mirrors `#Draft` from `draft.cue`.
public struct Draft: Sendable, Codable {
    /// Unique identifier for this draft row. UUIDv7.
    public let id: UUID

    /// The editor session that produced this draft. Correlates with `EditorSession.id`.
    public let editorSessionId: UUID

    /// Reference to the Kubernetes resource whose manifest was being edited.
    /// `nil` for standalone Markdown sessions.
    public let resourceRef: ResourceRef?

    /// Format of the content snapshot.
    public let sourceFormat: EditorFormat

    /// Full content of the editor buffer at the time of the snapshot.
    /// Secret `data` / `stringData` values are replaced with `"[REDACTED]"`
    /// when `sensitiveContentRedacted == true`.
    public let content: String

    /// `true` when the Secret-redaction path was applied to `content`.
    public let sensitiveContentRedacted: Bool

    /// RFC3339 timestamp when this snapshot was persisted.
    public let savedAt: String

    /// `true` when written automatically by `DraftAutoSaver` (5-second debounce).
    /// `false` when the operator explicitly chose "Save draft".
    public let autoSaved: Bool

    public init(
        id: UUID = UUID(),
        editorSessionId: UUID,
        resourceRef: ResourceRef? = nil,
        sourceFormat: EditorFormat,
        content: String,
        sensitiveContentRedacted: Bool = false,
        savedAt: String,
        autoSaved: Bool = true
    ) {
        self.id = id
        self.editorSessionId = editorSessionId
        self.resourceRef = resourceRef
        self.sourceFormat = sourceFormat
        self.content = content
        self.sensitiveContentRedacted = sensitiveContentRedacted
        self.savedAt = savedAt
        self.autoSaved = autoSaved
    }
}
