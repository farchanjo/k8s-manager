// Domain/MenuBarTray.swift — app_shell bounded context
// DDD role: AggregateRoot (#MenuBarTray), ValueObject (#TrayMetricWidget, #TrayRefreshEvent)
// CUE source: docs/arch/contexts/app_shell/schemas/
//   menu_bar_tray.cue, tray_metric_widget.cue, tray_refresh_event.cue
// ADR ref: ADR-0022

import Foundation

// MARK: - MenuBarTray (AggregateRoot)

/// Aggregate root for the system menu bar status item and its NSPopover.
///
/// Persisted under `app_shell/menu_bar_tray` in `local_persistence`.
/// Transient `popoverState` is reconstructed as `.closed` on every cold launch.
public struct MenuBarTray: Sendable, Codable, Identifiable {

    public enum DisplayMode: String, Sendable, Codable {
        case activeCluster = "active_cluster"
        case allClustersSummary = "all_clusters_summary"
    }

    public enum IconState: String, Sendable, Codable {
        case online, degraded, offline
    }

    public enum RefreshInterval: Int, Sendable, Codable {
        case five = 5, fifteen = 15, thirty = 30, sixty = 60
    }

    public enum PopoverState: String, Sendable, Codable {
        case closed, opening, open, closing
    }

    /// UUIDv7 stable aggregate identity.
    public let id: String
    public var displayMode: DisplayMode
    /// Computed by `TrayPresenter` after each refresh cycle — not persisted.
    public var iconState: IconState
    public var refreshIntervalSeconds: RefreshInterval
    public var manualRefreshOnly: Bool
    public var backgroundRefreshEnabled: Bool
    public var popoverPinned: Bool
    /// RFC 3339 UTC timestamp of the last successful refresh. Absent before first cycle.
    public var lastRefreshedAtRFC3339: String?
    /// Transient — always `.closed` on cold launch.
    public var popoverState: PopoverState

    public init(
        id: String,
        displayMode: DisplayMode = .activeCluster,
        iconState: IconState = .online,
        refreshIntervalSeconds: RefreshInterval = .thirty,
        manualRefreshOnly: Bool = false,
        backgroundRefreshEnabled: Bool = false,
        popoverPinned: Bool = false,
        lastRefreshedAtRFC3339: String? = nil,
        popoverState: PopoverState = .closed
    ) {
        self.id = id
        self.displayMode = displayMode
        self.iconState = iconState
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.manualRefreshOnly = manualRefreshOnly
        self.backgroundRefreshEnabled = backgroundRefreshEnabled
        self.popoverPinned = popoverPinned
        self.lastRefreshedAtRFC3339 = lastRefreshedAtRFC3339
        self.popoverState = popoverState
    }

    /// Effective refresh interval doubles when the popover is closed and background refresh is enabled.
    public var effectiveRefreshIntervalSeconds: Int {
        let base = refreshIntervalSeconds.rawValue
        if backgroundRefreshEnabled, popoverState == .closed {
            return base * 2
        }
        return base
    }
}

// MARK: - TrayLayout

/// Ordered sequence of widget IDs rendered in the popover content area.
public struct TrayLayout: Sendable, Codable {
    public let widgetOrder: [String]

    public init(widgetOrder: [String]) {
        self.widgetOrder = widgetOrder
    }
}

// MARK: - TrayMetricWidget

/// Sum type representing a single widget in the NSPopover content area.
///
/// Widget definitions are authored in the CUE schema and not mutated at runtime.
public enum TrayMetricWidget: Sendable, Codable {
    case sparkline(SparklineWidget)
    case stackedBar(StackedBarWidget)
    case count(CountWidget)
    case recentMutations(RecentMutationsWidget)
    case activeSessions(ActiveSessionsWidget)

    public var id: String {
        switch self {
        case .sparkline(let w): return w.id
        case .stackedBar(let w): return w.id
        case .count(let w): return w.id
        case .recentMutations(let w): return w.id
        case .activeSessions(let w): return w.id
        }
    }
}

// MARK: Widget variants

public struct SparklineWidget: Sendable, Codable, Identifiable {
    public enum YUnit: String, Sendable, Codable {
        case percent, bytes, count, perSecond = "per_second"
    }

    public let id: String
    public let title: String
    public let promQLTemplate: String
    public let rangeMinutes: Int
    public let samplePoints: Int
    public let yUnit: YUnit

    public init(
        id: String, title: String, promQLTemplate: String,
        rangeMinutes: Int = 60, samplePoints: Int = 60, yUnit: YUnit = .count
    ) {
        self.id = id; self.title = title; self.promQLTemplate = promQLTemplate
        self.rangeMinutes = rangeMinutes; self.samplePoints = samplePoints; self.yUnit = yUnit
    }
}

public struct BarSegment: Sendable, Codable {
    public enum Color: String, Sendable, Codable { case healthy, warning, error, info }
    public let label: String
    public let color: Color
    public let promQLTemplate: String

    public init(label: String, color: Color, promQLTemplate: String) {
        self.label = label; self.color = color; self.promQLTemplate = promQLTemplate
    }
}

public struct StackedBarWidget: Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let segments: [BarSegment]

    public init(id: String, title: String, segments: [BarSegment]) {
        self.id = id; self.title = title; self.segments = segments
    }
}

public struct StatusThreshold: Sendable, Codable {
    public enum Operator: String, Sendable, Codable { case lessThan = "less_than", greaterThan = "greater_than", equal }
    public enum Color: String, Sendable, Codable { case healthy, warning, error, info }
    public let `operator`: Operator
    public let threshold: Double
    public let color: Color

    public init(operator op: Operator, threshold: Double, color: Color) {
        self.operator = op; self.threshold = threshold; self.color = color
    }
}

public struct CountWidget: Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let primaryQuery: String
    public let secondaryQuery: String?
    public let statusMapping: [StatusThreshold]

    public init(
        id: String, title: String, primaryQuery: String,
        secondaryQuery: String? = nil, statusMapping: [StatusThreshold] = []
    ) {
        self.id = id; self.title = title; self.primaryQuery = primaryQuery
        self.secondaryQuery = secondaryQuery; self.statusMapping = statusMapping
    }
}

public struct RecentMutationsWidget: Sendable, Codable, Identifiable {
    public let id: String
    public let limit: Int

    public init(id: String, limit: Int = 5) {
        self.id = id; self.limit = limit
    }
}

public struct ActiveSessionsWidget: Sendable, Codable, Identifiable {
    public enum SessionType: String, Sendable, Codable {
        case portForward = "port_forward", terminal, chat
    }

    public let id: String
    public let sessionType: SessionType
    public let showCount: Bool

    public init(id: String, sessionType: SessionType, showCount: Bool = true) {
        self.id = id; self.sessionType = sessionType; self.showCount = showCount
    }
}

// MARK: - TrayRefreshEvent

/// Sum type for all discrete events in the tray refresh state machine.
///
/// Emitted by `TrayRefreshScheduler`; never persisted. No credential material allowed.
public enum TrayRefreshEvent: Sendable {
    case requested(cause: RefreshCause)
    case succeeded(durationMillis: Int, widgetCount: Int)
    case failed(widgetId: String?, reason: String)
    case paused(cause: PauseCause)
    case resumed

    public enum RefreshCause: String, Sendable, Codable {
        case interval, manual, contextSwitch = "context_switch", appForeground = "app_foreground"
    }

    public enum PauseCause: String, Sendable, Codable {
        case lidClosed = "lid_closed", lowPower = "low_power"
        case networkUnreachable = "network_unreachable", operatorPause = "operator_pause"
    }
}
