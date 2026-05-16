// Domain/DrilldownEvent.swift — analytics_dashboard bounded context
// DDD role: ValueObject (discriminated union)
// Spec:      docs/arch/contexts/analytics_dashboard/schemas/drilldown_event.cue
// ADR ref:   ADR-0024 (Analytics Dashboard Bounded Context)
//
// Swift 6 strict concurrency — all types are value types conforming to Sendable.

import Foundation

// MARK: - DrillEventTimeRange

/// Valid look-back windows for `DrillToEvents`.
///
/// Mirrors `15 | 60 | 360 | 1440` in `drilldown_event.cue#DrillToEvents`.
public enum DrillEventTimeRange: Int, Sendable, Codable, Hashable, CaseIterable {
    case fifteenMinutes = 15
    case oneHour = 60
    case sixHours = 360
    case oneDay = 1440
}

// MARK: - DrillDownEvent

/// Closed discriminated union of all navigation intents emitted by interactive widgets.
///
/// `DrillDownNavigator` domain service handles each variant: scope change, log viewer
/// open, YAML viewer open, or filtered event timeline open.
///
/// Invariant: `DrillToLogs` and `DrillToEvents` always carry the x-axis value from
/// the click as `timestampRFC3339` — never a server-clock value (spec §4).
///
/// Mirrors `#DrillDownEvent` in `drilldown_event.cue`.
public enum DrillDownEvent: Sendable, Codable, Hashable {
    /// Navigate the dashboard to a different `DashboardScope`.
    case drillToScope(DrillToScope)
    /// Open the log viewer at a specific timestamp.
    case drillToLogs(DrillToLogs)
    /// Open the YAML resource viewer for a specific resource.
    case drillToYAML(DrillToYAML)
    /// Open a filtered event timeline for a specific resource and time range.
    case drillToEvents(DrillToEvents)

    // MARK: Codable

    private enum CodingKeys: String, CodingKey { case eventKind }

    private enum EventKind: String, Codable {
        case drillToScope = "drill_to_scope"
        case drillToLogs = "drill_to_logs"
        case drillToYAML = "drill_to_yaml"
        case drillToEvents = "drill_to_events"
    }

    public init(from decoder: any Decoder) throws {
        let peek = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try peek.decode(EventKind.self, forKey: .eventKind)
        let single = try decoder.singleValueContainer()
        switch kind {
        case .drillToScope:
            self = .drillToScope(try single.decode(DrillToScope.self))
        case .drillToLogs:
            self = .drillToLogs(try single.decode(DrillToLogs.self))
        case .drillToYAML:
            self = .drillToYAML(try single.decode(DrillToYAML.self))
        case .drillToEvents:
            self = .drillToEvents(try single.decode(DrillToEvents.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .drillToScope(let e):   try single.encode(e)
        case .drillToLogs(let e):    try single.encode(e)
        case .drillToYAML(let e):    try single.encode(e)
        case .drillToEvents(let e):  try single.encode(e)
        }
    }

    /// The provenance dashboard identifier common to all variants.
    public var sourceDashboardId: String {
        switch self {
        case .drillToScope(let e):   return e.sourceDashboardId
        case .drillToLogs(let e):    return e.sourceDashboardId
        case .drillToYAML(let e):    return e.sourceDashboardId
        case .drillToEvents(let e):  return e.sourceDashboardId
        }
    }

    /// The provenance widget identifier common to all variants.
    public var sourceWidgetId: String {
        switch self {
        case .drillToScope(let e):   return e.sourceWidgetId
        case .drillToLogs(let e):    return e.sourceWidgetId
        case .drillToYAML(let e):    return e.sourceWidgetId
        case .drillToEvents(let e):  return e.sourceWidgetId
        }
    }
}

// MARK: - DrillToScope

/// Navigates the dashboard to a different `DashboardScope`.
///
/// Emitted by topology graph node clicks, top-list row clicks, count tile clicks,
/// and stacked bar segment clicks.
///
/// Mirrors `#DrillToScope` in `drilldown_event.cue`.
public struct DrillToScope: Sendable, Codable, Hashable {
    public let eventKind: String
    /// Dashboard aggregate root that owns the source widget.
    public let sourceDashboardId: String
    /// Widget identifier within the source dashboard layout.
    public let sourceWidgetId: String
    /// The dashboard scope the navigator should transition to.
    public let targetScope: DashboardScope

    /// Designated initialiser.
    public init(sourceDashboardId: String, sourceWidgetId: String, targetScope: DashboardScope) {
        self.eventKind = "drill_to_scope"
        self.sourceDashboardId = sourceDashboardId
        self.sourceWidgetId = sourceWidgetId
        self.targetScope = targetScope
    }
}

// MARK: - DrillToLogs

/// Opens the log viewer in `resource_browser` at a specific timestamp.
///
/// Emitted by `LogErrorRateWidget` spike clicks and heatmap column clicks.
/// `AuditTimelinePort` opens the log stream positioned at `timestampRFC3339 ± 30s`.
///
/// Mirrors `#DrillToLogs` in `drilldown_event.cue`.
public struct DrillToLogs: Sendable, Codable, Hashable {
    public let eventKind: String
    /// Dashboard aggregate root that owns the source widget.
    public let sourceDashboardId: String
    /// Widget identifier within the source dashboard layout.
    public let sourceWidgetId: String
    /// Kubernetes namespace containing the target pod(s).
    public let namespace: String
    /// Label selector identifying the target pod(s).
    public let podName: String
    /// RFC 3339 timestamp at which the log viewer should be positioned.
    ///
    /// Always the x-axis value at the click point — never a server-clock value (spec §4).
    public let timestampRFC3339: String

    /// Designated initialiser.
    public init(
        sourceDashboardId: String,
        sourceWidgetId: String,
        namespace: String,
        podName: String,
        timestampRFC3339: String
    ) {
        self.eventKind = "drill_to_logs"
        self.sourceDashboardId = sourceDashboardId
        self.sourceWidgetId = sourceWidgetId
        self.namespace = namespace
        self.podName = podName
        self.timestampRFC3339 = timestampRFC3339
    }
}

// MARK: - DrillToYAML

/// Opens the YAML resource viewer in `resource_browser` for a specific resource.
///
/// Emitted by topology graph node clicks and diff viewer side-panel clicks.
///
/// Mirrors `#DrillToYAML` in `drilldown_event.cue`.
public struct DrillToYAML: Sendable, Codable, Hashable {
    public let eventKind: String
    /// Dashboard aggregate root that owns the source widget.
    public let sourceDashboardId: String
    /// Widget identifier within the source dashboard layout.
    public let sourceWidgetId: String
    /// The resource to display in the YAML viewer.
    public let resourceRef: ResourceRef

    /// Designated initialiser.
    public init(sourceDashboardId: String, sourceWidgetId: String, resourceRef: ResourceRef) {
        self.eventKind = "drill_to_yaml"
        self.sourceDashboardId = sourceDashboardId
        self.sourceWidgetId = sourceWidgetId
        self.resourceRef = resourceRef
    }
}

// MARK: - DrillToEvents

/// Opens a filtered event timeline scoped to a specific resource and time range.
///
/// Emitted by workload replica chart clicks, node condition indicator clicks,
/// and pod restart count tile clicks.
///
/// Mirrors `#DrillToEvents` in `drilldown_event.cue`.
public struct DrillToEvents: Sendable, Codable, Hashable {
    public let eventKind: String
    /// Dashboard aggregate root that owns the source widget.
    public let sourceDashboardId: String
    /// Widget identifier within the source dashboard layout.
    public let sourceWidgetId: String
    /// The resource whose events should be displayed.
    public let resourceRef: ResourceRef
    /// Look-back window in minutes from the click timestamp. Default: 60.
    public let timeRangeMinutes: DrillEventTimeRange

    /// Designated initialiser.
    public init(
        sourceDashboardId: String,
        sourceWidgetId: String,
        resourceRef: ResourceRef,
        timeRangeMinutes: DrillEventTimeRange = .oneHour
    ) {
        self.eventKind = "drill_to_events"
        self.sourceDashboardId = sourceDashboardId
        self.sourceWidgetId = sourceWidgetId
        self.resourceRef = resourceRef
        self.timeRangeMinutes = timeRangeMinutes
    }
}
