// Domain/EditorSession.swift — resource_browser bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/resource_browser/schemas/editor_session.cue
// ADR ref: ADR-0030 (integrated editor MD / YAML / JSON)

import Foundation

// MARK: - ResourceRef

/// Identifies the Kubernetes resource being edited.
///
/// `nil` for Markdown-only editor sessions (e.g., standalone README).
/// Mirrors `#ResourceRef` from `editor_session.cue`.
public struct ResourceRef: Hashable, Sendable, Codable {
    /// API version string (e.g. `"apps/v1"` or `"v1"`).
    public let apiVersion: String

    /// Kubernetes kind name (e.g. `"Deployment"`, `"ConfigMap"`).
    public let kind: String

    /// Namespace of the resource. `nil` for cluster-scoped resources.
    public let namespace: String?

    /// Name of the resource instance.
    public let name: String

    public init(
        apiVersion: String,
        kind: String,
        namespace: String?,
        name: String
    ) {
        self.apiVersion = apiVersion
        self.kind = kind
        self.namespace = namespace
        self.name = name
    }
}

// MARK: - Diagnostic

/// A single validation finding within the editor.
///
/// Produced by `RealtimeValidatorService` and `K8sSchemaValidator`.
/// Mirrors `#Diagnostic` from `editor_session.cue`.
public struct Diagnostic: Hashable, Sendable, Codable {
    /// Severity of the finding.
    public let severity: Severity

    /// 1-based line number within the document.
    public let lineNumber: Int

    /// 1-based column number. `nil` when the source lacks column precision.
    public let columnNumber: Int?

    /// Human-readable description of the finding.
    public let message: String

    /// Service that produced this diagnostic.
    public let source: DiagnosticSource

    public init(
        severity: Severity,
        lineNumber: Int,
        columnNumber: Int? = nil,
        message: String,
        source: DiagnosticSource
    ) {
        self.severity = severity
        self.lineNumber = lineNumber
        self.columnNumber = columnNumber
        self.message = message
        self.source = source
    }

    /// Severity levels for validation findings.
    public enum Severity: String, Hashable, Sendable, Codable {
        case error, warning, info
    }

    /// Service that produced a diagnostic.
    public enum DiagnosticSource: String, Hashable, Sendable, Codable {
        case yamlParser = "yaml-parser"
        case jsonParser = "json-parser"
        case k8sSchema = "k8s-schema"
        case jsonSchema = "json-schema"
        case linter
    }
}

// MARK: - FieldConflict

/// Server-side apply field ownership conflict returned by the API server (HTTP 409).
///
/// Mirrors `#FieldConflict` from `editor_session.cue`.
public struct FieldConflict: Hashable, Sendable, Codable {
    /// JSON Pointer path to the conflicting field (e.g. `"/spec/replicas"`).
    public let fieldPath: String

    /// Field manager that currently owns this field on the server.
    public let currentManager: String

    /// Field manager attempting to take ownership.
    /// Defaults to `FieldManager.k8sManager`.
    public let attemptingManager: String

    public init(
        fieldPath: String,
        currentManager: String,
        attemptingManager: String = FieldManager.k8sManager
    ) {
        self.fieldPath = fieldPath
        self.currentManager = currentManager
        self.attemptingManager = attemptingManager
    }
}

// MARK: - EditorFormat

/// Format of the content being edited.
public enum EditorFormat: String, Hashable, Sendable, Codable {
    case yaml, json, markdown
}

// MARK: - EditorState

/// Discriminated union driving the editor state machine.
///
/// Nine states modelling the full editing lifecycle (idle → loading → editing
/// → validating → dryRunning → dryRunComplete → applying → applied → error).
/// Mirrors `#EditorState` from `editor_session.cue`.
public enum EditorState: Hashable, Sendable, Codable {
    /// Editor is open in read-only mode. No editing has started.
    case idle

    /// Editor is fetching the resource manifest from the cluster.
    case loading

    /// Operator is actively editing. Diagnostics updated continuously.
    case editing(diagnostics: [Diagnostic])

    /// A validation pass is in progress (100 ms debounce).
    case validating(diagnostics: [Diagnostic])

    /// A server-side dry-run PATCH is in-flight.
    case dryRunning

    /// Dry-run response received. Diff preview and conflicts available.
    case dryRunComplete(diffPreview: String, conflicts: [FieldConflict])

    /// The apply PATCH is in-flight (operator confirmed).
    case applying

    /// Apply operation completed (success or failure).
    case applied(outcome: ApplyOutcome, outcomeDetail: String)

    /// Non-recoverable error occurred. Operator can dismiss to idle or editing.
    case error(errorDetail: String)

    /// Outcome of an apply operation.
    public enum ApplyOutcome: String, Hashable, Sendable, Codable {
        case succeeded, failed
    }
}

// MARK: - EditorSession

/// Aggregate root for the integrated editor. One instance per editor invocation.
///
/// Held in memory for the duration of the editing session; discarded when the
/// editor is closed. Persistence is handled by `Draft` (a separate entity).
///
/// Mirrors `#EditorSession` from `editor_session.cue`.
public struct EditorSession: Sendable, Codable {
    /// Unique identifier for this editing session. UUIDv7.
    public let id: UUID

    /// Active Kubernetes context when the session was opened.
    public let kubernetesContextId: UUID

    /// Reference to the Kubernetes resource being edited.
    /// `nil` for standalone Markdown sessions.
    public let resourceRef: ResourceRef?

    /// Format of the content being edited.
    public let sourceFormat: EditorFormat

    /// Current content in the editor buffer (mutable during editing).
    public var currentContent: String

    /// Original content as fetched from the cluster. Immutable after session creation.
    public let originalContent: String

    /// `true` when `currentContent` differs from `originalContent`.
    public var isDirty: Bool { currentContent != originalContent }

    /// Current state of the editor state machine.
    public var state: EditorState

    /// RFC3339 timestamp when the session was opened.
    public let openedAt: String

    /// RFC3339 timestamp of the last content modification.
    public var lastModifiedAt: String

    /// RFC3339 timestamp of the last diagnostics run. `nil` before first pass.
    public var lastDiagnosticsRunAt: String?

    /// Debounce interval in milliseconds (50–5000). Drives dry-run requests.
    public let debounceMs: Int

    public init(
        id: UUID = UUID(),
        kubernetesContextId: UUID,
        resourceRef: ResourceRef? = nil,
        sourceFormat: EditorFormat,
        currentContent: String,
        originalContent: String,
        state: EditorState = .idle,
        openedAt: String,
        lastModifiedAt: String,
        lastDiagnosticsRunAt: String? = nil,
        debounceMs: Int = 500
    ) {
        self.id = id
        self.kubernetesContextId = kubernetesContextId
        self.resourceRef = resourceRef
        self.sourceFormat = sourceFormat
        self.currentContent = currentContent
        self.originalContent = originalContent
        self.state = state
        self.openedAt = openedAt
        self.lastModifiedAt = lastModifiedAt
        self.lastDiagnosticsRunAt = lastDiagnosticsRunAt
        self.debounceMs = max(50, min(5000, debounceMs))
    }
}
