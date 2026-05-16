// Domain/ResourceView.swift — resource_browser bounded context
// DDD role: ReadModel
// CUE source: docs/arch/contexts/resource_browser/schemas/resource_view.cue
// ADR ref: ADR-0013 (kind catalogue)

import Foundation

// MARK: - StatusCondition

/// Projection of a single entry in a Kubernetes `.status.conditions` array.
///
/// Mirrors `#StatusCondition` from `resource_view.cue`.
public struct StatusCondition: Hashable, Sendable, Codable {
    /// Condition type (e.g. `"Ready"`, `"Available"`, `"Progressing"`).
    public let conditionType: String

    /// Condition status — `"True"`, `"False"`, or `"Unknown"`.
    public let status: ConditionStatus

    /// Short CamelCase reason code. May be empty for older API objects.
    public let reason: String

    /// Human-readable message. May be empty.
    public let message: String

    /// RFC3339 timestamp of the most recent status transition.
    public let lastTransitionTime: String

    public init(
        conditionType: String,
        status: ConditionStatus,
        reason: String,
        message: String,
        lastTransitionTime: String
    ) {
        self.conditionType = conditionType
        self.status = status
        self.reason = reason
        self.message = message
        self.lastTransitionTime = lastTransitionTime
    }

    /// Closed set of `.status.conditions[].status` values.
    public enum ConditionStatus: String, Hashable, Sendable, Codable {
        case `true` = "True"
        case `false` = "False"
        case unknown = "Unknown"
    }
}

// MARK: - EventSummary

/// Lightweight projection of a single Kubernetes Event object.
///
/// Used in the recent events list in `ResourceDetail`.
/// Mirrors `#EventSummary` from `resource_view.cue`.
public struct EventSummary: Hashable, Sendable, Codable {
    /// Short reason string (e.g. `"Scheduled"`, `"Pulled"`, `"BackOff"`).
    public let reason: String

    /// Human-readable event message.
    public let message: String

    /// Kubernetes event type.
    public let eventType: EventType

    /// Number of times this event has occurred. Always >= 1.
    public let count: Int

    /// RFC3339 timestamp of the most recent occurrence.
    public let lastTimestamp: String

    public init(
        reason: String,
        message: String,
        eventType: EventType,
        count: Int,
        lastTimestamp: String
    ) {
        self.reason = reason
        self.message = message
        self.eventType = eventType
        self.count = count
        self.lastTimestamp = lastTimestamp
    }

    /// Kubernetes event severity level.
    public enum EventType: String, Hashable, Sendable, Codable {
        case normal = "Normal"
        case warning = "Warning"
    }
}

// MARK: - ResourceListItem

/// Lightweight read model projected from a Kubernetes resource manifest.
///
/// Carries enough information to populate a table row and support sorting,
/// filtering, and selection, without loading the full manifest into memory.
/// A new projection is emitted for every watch event that affects the resource.
///
/// Mirrors `#ResourceListItem` from `resource_view.cue`.
public struct ResourceListItem: Hashable, Sendable, Codable {
    /// UUIDv7 derived deterministically from (contextId, namespace, kind, name).
    public let id: UUID

    /// Kubernetes API type of this resource.
    public let gvk: GroupVersionKind

    /// Kubernetes namespace. `nil` for cluster-scoped resources.
    public let namespace: String?

    /// Kubernetes resource name within its namespace or cluster scope.
    public let name: String

    /// Kubernetes object UID as assigned by the API server.
    public let uid: String

    /// RFC3339 creation timestamp.
    public let creationTimestamp: String

    /// Concise, human-readable status string derived from `.status` (kind-specific).
    public let status: String

    /// Whole seconds elapsed since `creationTimestamp`. Always >= 0.
    public let ageSeconds: Int

    /// Full set of `metadata.labels`. May be empty.
    public let labels: [String: String]

    /// Full set of `metadata.annotations`. May be empty.
    public let annotations: [String: String]

    public init(
        id: UUID,
        gvk: GroupVersionKind,
        namespace: String?,
        name: String,
        uid: String,
        creationTimestamp: String,
        status: String,
        ageSeconds: Int,
        labels: [String: String] = [:],
        annotations: [String: String] = [:]
    ) {
        self.id = id
        self.gvk = gvk
        self.namespace = namespace
        self.name = name
        self.uid = uid
        self.creationTimestamp = creationTimestamp
        self.status = status
        self.ageSeconds = ageSeconds
        self.labels = labels
        self.annotations = annotations
    }
}

// MARK: - ResourceDetail

/// Full read model for a single resource opened in the detail panel.
///
/// Carries the original JSON manifest plus structured projections of the most
/// diagnostically useful sub-objects. A new projection is emitted when the
/// resource is re-fetched or when a watch event carries a full object.
///
/// Mirrors `#ResourceDetail` from `resource_view.cue`.
public struct ResourceDetail: Hashable, Sendable, Codable {
    /// The list-row projection for this resource, kept in sync.
    public let listItem: ResourceListItem

    /// Full resource manifest as returned by the API server, serialised as JSON.
    public let rawJSON: String

    /// Parsed `.status.conditions` array. Empty when not applicable.
    public let conditions: [StatusCondition]

    /// Recent events whose `involvedObject.uid` matches this resource's uid,
    /// ordered by `lastTimestamp` descending, capped at 50.
    public let recentEvents: [EventSummary]

    public init(
        listItem: ResourceListItem,
        rawJSON: String,
        conditions: [StatusCondition] = [],
        recentEvents: [EventSummary] = []
    ) {
        self.listItem = listItem
        self.rawJSON = rawJSON
        self.conditions = conditions
        self.recentEvents = recentEvents
    }
}
