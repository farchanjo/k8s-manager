// Actors/DraftAutoSaver.swift — resource_browser bounded context
// DDD role: DomainService (actor)
// ADR refs: ADR-0030 (integrated editor, auto-save every 5 s while isDirty)

import Dependencies
import Foundation
import Logging

// MARK: - DraftAutoSaver

/// Debounced auto-save for editor sessions.
///
/// Callers invoke `registerEdit(sessionId:content:)` on each keystroke.
/// The actor coalesces edits and writes a `Draft` to `DraftStoragePort`
/// at most once per `saveInterval` (default 5 seconds).
///
/// Secret-value redaction: when `resourceRef.kind` is `"Secret"`, the actor
/// replaces `data:` and `stringData:` block values with `"[REDACTED]"` before
/// persisting (ADR-0030 §security-invariant).
public actor DraftAutoSaver {

    // MARK: - Dependencies

    @Dependency(\.draftStorage) private var storagePort

    // MARK: - State

    private var pendingEdits: [UUID: PendingEdit] = [:]
    private var saveTask: Task<Void, Never>?

    private let saveInterval: TimeInterval
    private let logger: Logger

    // MARK: - Nested types

    private struct PendingEdit: Sendable {
        let sessionId: UUID
        let resourceRef: ResourceRef?
        let sourceFormat: EditorFormat
        let content: String
        let isDirty: Bool
    }

    // MARK: - Initialiser

    /// Creates the auto-saver.
    ///
    /// - Parameters:
    ///   - saveInterval: Minimum seconds between consecutive auto-saves.
    ///     Defaults to 5.0 per ADR-0030.
    ///   - logger: Optional logger.
    public init(
        saveInterval: TimeInterval = 5.0,
        logger: Logger = Logger(label: "resource_browser.draft_auto_saver")
    ) {
        self.saveInterval = saveInterval
        self.logger = logger
    }

    // MARK: - Public API

    /// Records a content change for `sessionId` and schedules a debounced save.
    ///
    /// Multiple calls within `saveInterval` are coalesced; only the last
    /// snapshot is persisted. When `isDirty` is `false`, any pending edit for
    /// the session is discarded without a save.
    ///
    /// - Parameters:
    ///   - sessionId: The `EditorSession.id` this edit belongs to.
    ///   - content: Current content of the editor buffer.
    ///   - resourceRef: Kubernetes resource reference (used for kind-based redaction).
    ///   - sourceFormat: Format of the content (YAML / JSON / Markdown).
    ///   - isDirty: `true` when the content differs from the original server manifest.
    public func registerEdit(
        sessionId: UUID,
        content: String,
        resourceRef: ResourceRef? = nil,
        sourceFormat: EditorFormat = .yaml,
        isDirty: Bool
    ) {
        if isDirty {
            pendingEdits[sessionId] = PendingEdit(
                sessionId: sessionId,
                resourceRef: resourceRef,
                sourceFormat: sourceFormat,
                content: content,
                isDirty: isDirty
            )
            scheduleDebounce()
        } else {
            pendingEdits.removeValue(forKey: sessionId)
        }
    }

    /// Forces an immediate save of any pending edit for `sessionId`.
    ///
    /// Used when the editor pane closes to avoid data loss. No-op when there
    /// is no pending edit for the session.
    ///
    /// - Parameter sessionId: The `EditorSession.id` to flush.
    public func flush(sessionId: UUID) async {
        guard let edit = pendingEdits[sessionId] else { return }
        pendingEdits.removeValue(forKey: sessionId)
        await persistDraft(from: edit, autoSaved: true)
    }

    // MARK: - Private

    private func scheduleDebounce() {
        // Cancel any in-flight timer so only the last edit within the window fires.
        saveTask?.cancel()
        let interval = saveInterval
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            await self?.flushAll()
        }
    }

    private func flushAll() async {
        let edits = pendingEdits
        pendingEdits.removeAll()
        for edit in edits.values {
            await persistDraft(from: edit, autoSaved: true)
        }
    }

    private func persistDraft(from edit: PendingEdit, autoSaved: Bool) async {
        let redacted = isSecret(edit.resourceRef) ? redactSecretValues(edit.content) : false
        let content = redacted ? applyRedaction(to: edit.content) : edit.content
        let savedAt = ISO8601DateFormatter().string(from: Date())

        let draft = Draft(
            editorSessionId: edit.sessionId,
            resourceRef: edit.resourceRef,
            sourceFormat: edit.sourceFormat,
            content: content,
            sensitiveContentRedacted: redacted,
            savedAt: savedAt,
            autoSaved: autoSaved
        )

        do {
            try await storagePort.save(draft)
            logger.debug("Auto-saved draft for session=\(edit.sessionId)")
        } catch {
            logger.warning("Failed to auto-save draft for session=\(edit.sessionId): \(error)")
        }
    }

    private func isSecret(_ ref: ResourceRef?) -> Bool {
        ref?.kind == "Secret"
    }

    private func redactSecretValues(_ content: String) -> Bool {
        content.contains("data:") || content.contains("stringData:")
    }

    private func applyRedaction(to content: String) -> String {
        var lines = content.components(separatedBy: "\n")
        var insideDataBlock = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("data:") || trimmed.hasPrefix("stringData:") {
                insideDataBlock = true
                continue
            }
            if insideDataBlock {
                if trimmed.contains(":") && !trimmed.hasPrefix("-") {
                    let indent = String(line.prefix(while: { $0 == " " }))
                    let key = trimmed.components(separatedBy: ":").first ?? trimmed
                    lines[i] = "\(indent)\(key): [REDACTED]"
                } else {
                    insideDataBlock = false
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
