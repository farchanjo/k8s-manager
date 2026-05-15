// Domain/ClusterSession.swift — cluster_connectivity bounded context
// DDD role: AggregateRoot (per ADR-0025)
// CUE source: docs/arch/contexts/cluster_connectivity/schemas/cluster_session.cue

import Foundation
import SharedKernel

// MARK: - LifecycleState

/// Operational state of a cluster session.
///
/// Mirrors `#LifecycleState` from `cluster_session.cue`.
/// Legal transitions: `connecting → connected → degraded → disconnected → terminating`.
public enum LifecycleState: String, Hashable, Sendable, Codable {
    case connecting
    case connected
    case degraded
    case disconnected
    case terminating
}

// MARK: - PoolStats

/// Point-in-time snapshot of the HTTPClient connection pool metrics.
///
/// Mirrors `#PoolStats` from `cluster_session.cue`. Immutable once
/// constructed (ValueObject).
public struct PoolStats: Hashable, Sendable, Codable {
    /// Open but idle TCP connections awaiting reuse.
    public let idleConnections: Int

    /// Connections currently in use by an in-flight HTTP request.
    public let activeConnections: Int

    /// HTTP requests currently awaiting a response from the API server.
    public let requestsInFlight: Int

    /// Cumulative count of successfully completed HTTP requests.
    public let requestsCompleted: Int

    /// Cumulative count of HTTP requests that resulted in a transport-level
    /// error (excludes HTTP 4xx/5xx).
    public let requestsFailed: Int

    public init(
        idleConnections: Int = 0,
        activeConnections: Int = 0,
        requestsInFlight: Int = 0,
        requestsCompleted: Int = 0,
        requestsFailed: Int = 0
    ) {
        self.idleConnections = idleConnections
        self.activeConnections = activeConnections
        self.requestsInFlight = requestsInFlight
        self.requestsCompleted = requestsCompleted
        self.requestsFailed = requestsFailed
    }
}

// MARK: - WatchStreamStatus / WatchStreamRef

/// Operational status of a Kubernetes watch stream.
public enum WatchStreamStatus: String, Hashable, Sendable, Codable {
    case active, reconnecting, closed
}

/// Lightweight reference to an active Kubernetes watch stream.
///
/// Mirrors `#WatchStreamRef` from `cluster_session.cue` (ValueObject).
public struct WatchStreamRef: Hashable, Sendable, Codable {
    public let id: UUID
    public let apiGroup: String
    public let resourceKind: String
    public let namespace: String
    public let openedAt: String
    public let status: WatchStreamStatus

    public init(
        id: UUID,
        apiGroup: String,
        resourceKind: String,
        namespace: String,
        openedAt: String,
        status: WatchStreamStatus
    ) {
        self.id = id
        self.apiGroup = apiGroup
        self.resourceKind = resourceKind
        self.namespace = namespace
        self.openedAt = openedAt
        self.status = status
    }
}

// MARK: - ExecSessionStatus / ExecSessionRef

/// Operational status of an exec channel.
public enum ExecSessionStatus: String, Hashable, Sendable, Codable {
    case active, closing, closed
}

/// Lightweight reference to an active exec channel.
///
/// Mirrors `#ExecSessionRef` from `cluster_session.cue` (ValueObject).
public struct ExecSessionRef: Hashable, Sendable, Codable {
    public let id: UUID
    public let podName: String
    public let namespace: String
    public let containerName: String
    public let openedAt: String
    public let status: ExecSessionStatus

    public init(
        id: UUID,
        podName: String,
        namespace: String,
        containerName: String,
        openedAt: String,
        status: ExecSessionStatus
    ) {
        self.id = id
        self.podName = podName
        self.namespace = namespace
        self.containerName = containerName
        self.openedAt = openedAt
        self.status = status
    }
}

// MARK: - PortForwardStatus / PortForwardRef

/// Operational status of a port-forward listener.
public enum PortForwardStatus: String, Hashable, Sendable, Codable {
    case listening, closing, closed
}

/// Lightweight reference to an active port-forward listener.
///
/// Mirrors `#PortForwardRef` from `cluster_session.cue` (ValueObject).
public struct PortForwardRef: Hashable, Sendable, Codable {
    public let id: UUID
    public let targetKind: String
    public let targetName: String
    public let namespace: String
    public let localPort: Int
    public let remotePort: Int
    public let openedAt: String
    public let status: PortForwardStatus

    public init(
        id: UUID,
        targetKind: String,
        targetName: String,
        namespace: String,
        localPort: Int,
        remotePort: Int,
        openedAt: String,
        status: PortForwardStatus
    ) {
        self.id = id
        self.targetKind = targetKind
        self.targetName = targetName
        self.namespace = namespace
        self.localPort = localPort
        self.remotePort = remotePort
        self.openedAt = openedAt
        self.status = status
    }
}

// MARK: - TerminalSessionStatus / TerminalSessionRef

/// Operational status of a terminal session.
public enum TerminalSessionStatus: String, Hashable, Sendable, Codable {
    case active, closing, closed
}

/// Lightweight reference to an active terminal session.
///
/// Mirrors `#TerminalSessionRef` from `cluster_session.cue` (ValueObject).
public struct TerminalSessionRef: Hashable, Sendable, Codable {
    public let id: UUID
    public let displayName: String
    public let openedAt: String
    public let status: TerminalSessionStatus

    public init(
        id: UUID,
        displayName: String,
        openedAt: String,
        status: TerminalSessionStatus
    ) {
        self.id = id
        self.displayName = displayName
        self.openedAt = openedAt
        self.status = status
    }
}

// MARK: - ViewState

/// Per-cluster UI state that must survive a cluster switch and be restored on
/// cold launch.
///
/// Mirrors `#ViewState` from `cluster_session.cue`. Persisted atomically to
/// `~/.config/k8smanager/clusters/<clusterId>/view_state.json`.
public struct ViewState: Hashable, Sendable, Codable {
    /// Whether the left sidebar is expanded for this cluster.
    public let sidebarExpanded: Bool

    /// Normalised (0.0–1.0) vertical scroll position of the main content area.
    public let contentScrollPosition: Double

    /// Identifier of the currently selected tab in the detail panel.
    public let selectedDetailTab: String

    /// Namespace selector string currently applied in the resource browser.
    /// Empty string means all namespaces.
    public let namespaceFilter: String

    /// Current text in the search bar for this cluster.
    public let searchQuery: String

    public init(
        sidebarExpanded: Bool = true,
        contentScrollPosition: Double = 0.0,
        selectedDetailTab: String = "overview",
        namespaceFilter: String = "",
        searchQuery: String = ""
    ) {
        self.sidebarExpanded = sidebarExpanded
        self.contentScrollPosition = contentScrollPosition
        self.selectedDetailTab = selectedDetailTab
        self.namespaceFilter = namespaceFilter
        self.searchQuery = searchQuery
    }
}

// MARK: - ClusterSession

/// Aggregate root for one active cluster connection.
///
/// Mirrors `#ClusterSession` from `cluster_session.cue`. Owned by exactly one
/// `ClusterSessionActor`. Nothing in this aggregate is accessible from outside
/// that actor boundary.
public struct ClusterSession: Hashable, Sendable, Codable {
    /// UUIDv7 for this session instance. A new UUIDv7 is generated each time a
    /// session is opened, even for a previously open cluster.
    public let id: UUID

    /// Shared-kernel identifier of the Kubernetes cluster.
    public let clusterId: ClusterId

    /// UUIDv7 of the kubeconfig context entry active when this session was
    /// opened. Allows detection of context drift during a session.
    public let kubernetesContextId: UUID

    /// Current operational state.
    public let lifecycleState: LifecycleState

    /// RFC 3339 timestamp when this session was created.
    public let openedAt: String

    /// RFC 3339 timestamp of the most recent HTTP request or user interaction.
    public let lastUsedAt: String

    /// Minutes of inactivity before aggressive session teardown. `0` disables
    /// automatic teardown.
    public let idleTimeoutMinutes: Int

    /// Point-in-time connection pool snapshot.
    public let httpPoolStats: PoolStats

    /// Active watch streams.
    public let watchStreamRegistry: [WatchStreamRef]

    /// Active exec channels.
    public let execSessionRegistry: [ExecSessionRef]

    /// Active port-forward listeners.
    public let portForwardRegistry: [PortForwardRef]

    /// Active terminal sessions.
    public let terminalSessionRegistry: [TerminalSessionRef]

    /// Per-cluster UI state snapshot.
    public let viewState: ViewState

    public init(
        id: UUID = UUIDv7.generate(),
        clusterId: ClusterId,
        kubernetesContextId: UUID,
        lifecycleState: LifecycleState = .connecting,
        openedAt: String,
        lastUsedAt: String,
        idleTimeoutMinutes: Int = 0,
        httpPoolStats: PoolStats = PoolStats(),
        watchStreamRegistry: [WatchStreamRef] = [],
        execSessionRegistry: [ExecSessionRef] = [],
        portForwardRegistry: [PortForwardRef] = [],
        terminalSessionRegistry: [TerminalSessionRef] = [],
        viewState: ViewState = ViewState()
    ) {
        self.id = id
        self.clusterId = clusterId
        self.kubernetesContextId = kubernetesContextId
        self.lifecycleState = lifecycleState
        self.openedAt = openedAt
        self.lastUsedAt = lastUsedAt
        self.idleTimeoutMinutes = idleTimeoutMinutes
        self.httpPoolStats = httpPoolStats
        self.watchStreamRegistry = watchStreamRegistry
        self.execSessionRegistry = execSessionRegistry
        self.portForwardRegistry = portForwardRegistry
        self.terminalSessionRegistry = terminalSessionRegistry
        self.viewState = viewState
    }
}
