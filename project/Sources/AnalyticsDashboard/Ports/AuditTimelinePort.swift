// Ports/AuditTimelinePort.swift — analytics_dashboard bounded context
// DDD role: Port (outbound — consumes resource_browser + cluster_intelligence)
// Spec:      docs/arch/contexts/analytics_dashboard/domain/narrative.md §Ports
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Consumes resource_browser MutationAuditReadModel (kubectl apply/patch/delete mutations)
// and cluster_intelligence MCPInvocationLogReadModel (assistant tool call invocations).
// Used by EventTimeline and DebugTimeline widgets and by DrillDownNavigator
// for #DrillToLogs resolution.

import Foundation

// MARK: - AuditEventKind

/// Source classification for audit timeline entries.
public enum AuditEventKind: String, Sendable, Codable, Hashable, CaseIterable {
    /// Kubernetes object event from the API server.
    case k8sEvent = "k8s_event"
    /// kubectl apply/patch/delete mutation recorded by `resource_browser`.
    case mutationAudit = "mutation_audit"
    /// MCP assistant tool call invocation recorded by `cluster_intelligence`.
    case assistantToolCall = "assistant_tool_call"
}

// MARK: - AuditEntry

/// A single entry in the cross-source audit timeline.
public struct AuditEntry: Sendable, Codable, Hashable {
    /// Unique identifier for this entry.
    public let id: String
    /// Source classification.
    public let kind: AuditEventKind
    /// RFC 3339 timestamp when the event occurred.
    public let occurredAt: String
    /// Human-readable summary of the event.
    public let summary: String
    /// Optional Kubernetes resource coordinates referenced by this entry.
    public let resourceRef: ResourceRef?
    /// Raw detail payload (YAML fragment, log line, tool call arguments).
    public let detail: String?

    /// Designated initialiser.
    public init(
        id: String,
        kind: AuditEventKind,
        occurredAt: String,
        summary: String,
        resourceRef: ResourceRef? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.occurredAt = occurredAt
        self.summary = summary
        self.resourceRef = resourceRef
        self.detail = detail
    }
}

// MARK: - AuditTimelinePort

/// Provides chronological audit entries from `resource_browser` and `cluster_intelligence`.
///
/// Used by:
/// - `EventTimelineWidget` and `DebugTimeline` widgets.
/// - `DrillDownNavigator` for `DrillToLogs` resolution: opens the log stream
///   positioned at `timestampRFC3339 ± 30 s`.
///
/// Consumes `resource_browser` `MutationAuditReadModel` and
/// `cluster_intelligence` `MCPInvocationLogReadModel`.
public protocol AuditTimelinePort: Sendable {
    /// Returns audit entries matching the given time range and source filter.
    ///
    /// - Parameters:
    ///   - sourceFilter: Which event streams to include. `.all` merges all streams.
    ///   - rangeMinutes: Look-back window in minutes from `referenceTime`.
    ///   - referenceTime: RFC 3339 anchor time. Defaults to current time when `nil`.
    ///   - namespace: Optional namespace filter. `nil` returns all namespaces.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: Chronologically ordered list of audit entries, oldest first.
    /// - Throws: `AuditTimelineError` on storage or decode failure.
    func queryTimeline(
        sourceFilter: EventTimelineSourceFilter,
        rangeMinutes: Int,
        referenceTime: String?,
        namespace: String?,
        kubernetesContextId: String
    ) async throws -> [AuditEntry]

    /// Returns log lines for the given pod selector positioned around a timestamp.
    ///
    /// Used by `DrillDownNavigator` for `DrillToLogs` resolution.
    ///
    /// - Parameters:
    ///   - namespace: Kubernetes namespace containing the target pod(s).
    ///   - podSelector: Kubernetes label selector identifying the target pod(s).
    ///   - timestampRFC3339: RFC 3339 anchor timestamp (x-axis click value — spec §4).
    ///   - windowSeconds: Window ± seconds around the timestamp. Default: 30.
    ///   - kubernetesContextId: Cluster context identifier.
    /// - Returns: Log lines within the window, in chronological order.
    func queryLogs(
        namespace: String,
        podSelector: String,
        timestampRFC3339: String,
        windowSeconds: Int,
        kubernetesContextId: String
    ) async throws -> [String]
}

// MARK: - AuditTimelineError

/// Errors raised by `AuditTimelinePort` implementations.
public enum AuditTimelineError: Error, Sendable {
    /// Port has not been registered in this process.
    case unimplemented
    /// Storage read failure.
    case storageError(detail: String)
    /// Requested namespace does not exist.
    case namespaceNotFound(String)
    /// Connectivity failure when fetching from live cluster.
    case transportError(detail: String)
}

// MARK: - UnimplementedAuditTimelinePort

/// Crash-fast sentinel used as `liveValue` / `testValue` until an adapter registers.
public struct UnimplementedAuditTimelinePort: AuditTimelinePort {
    public init() {}

    public func queryTimeline(
        sourceFilter _: EventTimelineSourceFilter,
        rangeMinutes _: Int,
        referenceTime _: String?,
        namespace _: String?,
        kubernetesContextId _: String
    ) async throws -> [AuditEntry] {
        throw AuditTimelineError.unimplemented
    }

    public func queryLogs(
        namespace _: String,
        podSelector _: String,
        timestampRFC3339 _: String,
        windowSeconds _: Int,
        kubernetesContextId _: String
    ) async throws -> [String] {
        throw AuditTimelineError.unimplemented
    }
}
