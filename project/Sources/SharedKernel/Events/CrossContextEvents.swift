// CrossContextEvents.swift — 11 cross-context domain event types
// Bounded context: shared_kernel
// Spec:           docs/arch/contexts/_shared/schemas/domain_events.cue
// Decision:       ADR-0040
//
// Each struct mirrors exactly the fields declared in the corresponding CUE schema.
// Field names use camelCase Swift idiom; they match JSON keys via CodingKeys where
// the CUE name differs from lowerCamelCase (they do not in this schema, so the
// default synthesised Codable conformance is used throughout).
//
// Events included per the task brief (9 unique structs from 5 source contexts,
// expanded to 11 event types as specified):
//   cluster_connectivity  — ClusterSessionOpened, ClusterSessionClosed,
//                           WatchStreamReconnected
//   resource_browser      — MutationApplied, DraftSaved
//   local_persistence     — AuditEntryAppended
//   helm_management       — HelmManifestApplied, HelmRollbackInitiated,
//                           HelmRollbackCompleted
//   port_forwarding       — PortForwardEstablished
//   assistant_chat        — PromptInjectionSuspected (shared-subscriber re-export)

import Foundation

// MARK: - cluster_connectivity

/// Emitted when a cluster session is successfully established.
/// Source: `cluster_connectivity`. Consumed by: `app_shell`, `analytics_dashboard`,
/// `context_navigation`, `cluster_intelligence`.
public struct ClusterSessionOpened: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        /// Stable identifier of the cluster that opened the session.
        public let clusterId: String
        /// Kubeconfig context identifier active for this session.
        public let contextId: String
        /// RFC 3339 timestamp at which the session was opened.
        public let openedAt: String

        public init(clusterId: String, contextId: String, openedAt: String) {
            self.clusterId = clusterId
            self.contextId = contextId
            self.openedAt = openedAt
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

/// Emitted when a cluster session is torn down.
/// Source: `cluster_connectivity`. Consumed by: `app_shell`, `analytics_dashboard`,
/// `context_navigation`, `cluster_intelligence`.
public struct ClusterSessionClosed: DomainEvent {
    /// Reason the session was closed, enumerated in the CUE schema.
    public enum Reason: String, Sendable, Codable, Hashable {
        case operatorRequested = "operator-requested"
        case clusterUnreachable = "cluster-unreachable"
        case appQuit = "app-quit"
        case contextSwitch = "context-switch"
    }

    public struct Payload: Sendable, Codable, Hashable {
        public let clusterId: String
        /// RFC 3339 timestamp at which the session was closed.
        public let closedAt: String
        public let reason: Reason

        public init(clusterId: String, closedAt: String, reason: Reason) {
            self.clusterId = clusterId
            self.closedAt = closedAt
            self.reason = reason
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

/// Emitted when a Kubernetes API watch stream reconnects after a transient disconnection.
/// `resourceVersionBefore` is the RV used in the failed WATCH; `resourceVersionAfter` is
/// captured from the subsequent LIST (ADR-0036).
/// Source: `cluster_connectivity`. Consumed by: `analytics_dashboard`.
public struct WatchStreamReconnected: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        public let clusterId: String
        /// GVK kind being watched, e.g. `"Pod"`.
        public let kind: String
        public let resourceVersionBefore: String
        public let resourceVersionAfter: String
        /// Number of reconnection attempts before success (≥1).
        public let attempts: Int

        public init(
            clusterId: String,
            kind: String,
            resourceVersionBefore: String,
            resourceVersionAfter: String,
            attempts: Int
        ) {
            self.clusterId = clusterId
            self.kind = kind
            self.resourceVersionBefore = resourceVersionBefore
            self.resourceVersionAfter = resourceVersionAfter
            self.attempts = attempts
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

// MARK: - resource_browser

/// Emitted after a mutating Kubernetes operation is confirmed by the API server.
/// Source: `resource_browser`. Consumed by: `analytics_dashboard`, `local_persistence`,
/// `cluster_intelligence`, `app_shell`.
public struct MutationApplied: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        public let clusterId: String
        /// HTTP verb, e.g. `"apply"`, `"patch"`, `"delete"`.
        public let verb: String
        /// Group/Version/Kind string, e.g. `"apps/v1/Deployment"`.
        public let gvk: String
        public let namespace: String
        public let name: String
        /// SHA-256 hex digest of the applied manifest (64 lowercase hex chars).
        public let manifestDigest: String
        /// Confirmation dialog nonce per ADR-0012.
        public let confirmationToken: String

        public init(
            clusterId: String,
            verb: String,
            gvk: String,
            namespace: String,
            name: String,
            manifestDigest: String,
            confirmationToken: String
        ) {
            self.clusterId = clusterId
            self.verb = verb
            self.gvk = gvk
            self.namespace = namespace
            self.name = name
            self.manifestDigest = manifestDigest
            self.confirmationToken = confirmationToken
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

/// Emitted when an editor draft is auto-saved or explicitly saved by the operator.
/// Source: `resource_browser`. Consumed by: `app_shell`.
public struct DraftSaved: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        /// UUIDv7 identifier of the saved draft.
        public let draftId: String
        /// Editor session that owns this draft.
        public let editorSessionId: String
        /// `true` when the redaction policy stripped secret values (ADR-0010).
        public let sensitiveContentRedacted: Bool

        public init(draftId: String, editorSessionId: String, sensitiveContentRedacted: Bool) {
            self.draftId = draftId
            self.editorSessionId = editorSessionId
            self.sensitiveContentRedacted = sensitiveContentRedacted
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

// MARK: - local_persistence

/// Emitted when a new audit log entry is written to SQLite.
/// `previousEntryDigest` enables tamper detection via hash-chaining (ADR-0012).
/// Source: `local_persistence`. Subscribed by self-monitoring (ADR-0027).
public struct AuditEntryAppended: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        /// UUIDv7 identifier of the appended entry.
        public let auditEntryId: String
        /// SHA-256 hex digest of the previous entry for hash-chaining.
        public let previousEntryDigest: String

        public init(auditEntryId: String, previousEntryDigest: String) {
            self.auditEntryId = auditEntryId
            self.previousEntryDigest = previousEntryDigest
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

// MARK: - helm_management

/// Emitted when a Helm rollback command is dispatched to the Kubernetes API.
/// Source: `helm_management`. Consumed by: `analytics_dashboard`.
public struct HelmRollbackInitiated: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        public let clusterId: String
        public let releaseName: String
        /// Current installed revision being rolled back.
        public let fromRevision: Int
        /// Target revision to restore.
        public let toRevision: Int

        public init(clusterId: String, releaseName: String, fromRevision: Int, toRevision: Int) {
            self.clusterId = clusterId
            self.releaseName = releaseName
            self.fromRevision = fromRevision
            self.toRevision = toRevision
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

/// Emitted for each Kubernetes resource applied by the helm rollback orchestrator via
/// Server-Side Apply. One event per (gvk, namespace, name) triple.
///
/// Distinct from `MutationApplied` — the helm rollback flow has no confirmation-dialog
/// `confirmationToken`; merging the types would force a spurious optional field.
/// Source: `helm_management`. Consumed by: `analytics_dashboard`, `local_persistence`,
/// `app_shell`.
public struct HelmManifestApplied: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        public let clusterId: String
        public let releaseName: String
        public let toRevision: Int
        public let gvk: String
        public let namespace: String
        public let name: String
        /// SHA-256 hex digest of the rendered resource manifest at apply time.
        public let manifestDigest: String

        public init(
            clusterId: String,
            releaseName: String,
            toRevision: Int,
            gvk: String,
            namespace: String,
            name: String,
            manifestDigest: String
        ) {
            self.clusterId = clusterId
            self.releaseName = releaseName
            self.toRevision = toRevision
            self.gvk = gvk
            self.namespace = namespace
            self.name = name
            self.manifestDigest = manifestDigest
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

/// Emitted when the API server confirms or rejects a Helm rollback.
/// Source: `helm_management`. Consumed by: `analytics_dashboard`.
public struct HelmRollbackCompleted: DomainEvent {
    /// Terminal status of the rollback operation.
    public enum Status: String, Sendable, Codable, Hashable {
        case succeeded
        case aborted
        case partialFailure = "partial-failure"
    }

    public struct Payload: Sendable, Codable, Hashable {
        public let clusterId: String
        public let releaseName: String
        /// RFC 3339 timestamp at which the rollback was confirmed.
        public let completedAt: String
        public let status: Status

        public init(clusterId: String, releaseName: String, completedAt: String, status: Status) {
            self.clusterId = clusterId
            self.releaseName = releaseName
            self.completedAt = completedAt
            self.status = status
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

// MARK: - port_forwarding

/// Emitted when a local TCP listener successfully tunnels to the target pod via WebSocket.
/// Source: `port_forwarding`. Consumed by: `analytics_dashboard`, `app_shell`.
public struct PortForwardEstablished: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        public let clusterId: String
        public let namespace: String
        public let podName: String
        /// Local TCP port on which the listener was bound (1–65535).
        public let localPort: Int
        /// Remote port on the target pod (1–65535).
        public let remotePort: Int

        public init(
            clusterId: String,
            namespace: String,
            podName: String,
            localPort: Int,
            remotePort: Int
        ) {
            self.clusterId = clusterId
            self.namespace = namespace
            self.podName = podName
            self.localPort = localPort
            self.remotePort = remotePort
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}

// MARK: - assistant_chat (re-exported for shared subscribers)

/// Emitted by `assistant_chat` when the content-filter layer matches a denial pattern
/// in a cluster-origin string before LLM injection (ADR-0048, Layer 3).
///
/// Re-exported here so that `analytics_dashboard` and `app_shell` can subscribe
/// without importing the `assistant_chat` bounded context directly.
/// The full adversarial payload is never included; only pattern ID, source identity,
/// and a sanitised excerpt of at most 64 characters are carried.
public struct PromptInjectionSuspected: DomainEvent {
    public struct Payload: Sendable, Codable, Hashable {
        /// UUIDv7 identifier of the assistant session in which the match fired.
        public let sessionId: String
        /// First denial pattern that matched, e.g. `"PI-001"`.
        public let patternId: String
        /// `"<kind>/<name>"` of the originating Kubernetes resource.
        public let source: String
        /// First 64 characters of the sanitised payload (0–64 chars).
        public let sanitizedExcerpt: String
        /// Full set of pattern IDs that fired during this evaluation.
        public let matchedPatterns: [String]

        public init(
            sessionId: String,
            patternId: String,
            source: String,
            sanitizedExcerpt: String,
            matchedPatterns: [String]
        ) {
            self.sessionId = sessionId
            self.patternId = patternId
            self.source = source
            self.sanitizedExcerpt = sanitizedExcerpt
            self.matchedPatterns = matchedPatterns
        }
    }

    public let envelope: EventEnvelope
    public let payload: Payload

    public init(envelope: EventEnvelope, payload: Payload) {
        self.envelope = envelope
        self.payload = payload
    }
}
