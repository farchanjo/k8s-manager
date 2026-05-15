// Actors/ClusterSessionActor.swift — cluster_connectivity bounded context
// DDD role: DomainService (Swift actor — ADR-0011, ADR-0025)
// CUE source: docs/arch/contexts/cluster_connectivity/schemas/cluster_session.cue

import Foundation
import SharedKernel

// MARK: - SessionState

extension ClusterSessionActor {
    /// Operational lifecycle state owned by `ClusterSessionActor`.
    ///
    /// Mirrors `#LifecycleState` from `cluster_session.cue`. The actor is the
    /// sole authority for transitions; nothing outside the actor boundary can
    /// write to this value.
    public enum SessionState: Sendable, Equatable {
        /// Transport is being established (HTTPClient + EventLoopGroup not yet
        /// ready).
        case disconnected

        /// Waiting for the first successful health probe.
        case connecting

        /// HTTPClient ready and API server has confirmed reachability.
        case connected(serverVersion: String)

        /// Session is alive but a required capability is unavailable (e.g.,
        /// expired exec-plugin credential).
        case degraded(reason: String)

        /// All child tasks cancelled, all streams and listeners closed,
        /// HTTPClient shut down, EventLoopGroup stopped.
        case terminating
    }
}

// MARK: - ClusterSessionActor

/// Sole owner and lifecycle manager of a `ClusterSession` aggregate.
///
/// Per ADR-0025, exactly one `ClusterSessionActor` exists per active cluster.
/// All transport resources (HTTPClient handle, credential cache, watch-stream
/// registry, etc.) are held inside this actor and are never accessible from
/// outside its isolation boundary.
///
/// Connection orchestration is delegated entirely to ports — the actor calls
/// them; it does not implement them. The domain core never imports
/// `AsyncHTTPClient` or `SwiftkubeClient`.
public actor ClusterSessionActor {
    // MARK: Public state

    /// Shared-kernel identifier of the Kubernetes cluster this session targets.
    public let clusterId: ClusterId

    /// Current lifecycle state. Readable from any async context; writable only
    /// by this actor.
    public private(set) var state: SessionState

    // MARK: Private aggregate state

    /// Snapshot of connection-pool metrics. Updated every 30 s and on every
    /// request completion.
    private var poolStats: PoolStats

    /// Active watch streams registered for this session.
    private var watchStreamRegistry: [WatchStreamRef]

    /// Active exec channels registered for this session.
    private var execSessionRegistry: [ExecSessionRef]

    /// Active port-forward listeners registered for this session.
    private var portForwardRegistry: [PortForwardRef]

    /// Active terminal sessions registered for this session.
    private var terminalSessionRegistry: [TerminalSessionRef]

    /// Per-cluster UI state.
    private var viewState: ViewState

    // MARK: - Init

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
        self.state = .disconnected
        self.poolStats = PoolStats()
        self.watchStreamRegistry = []
        self.execSessionRegistry = []
        self.portForwardRegistry = []
        self.terminalSessionRegistry = []
        self.viewState = ViewState()
    }

    // MARK: - Lifecycle transitions

    /// Applies a new lifecycle state. Callers are responsible for ensuring
    /// the transition is legal per the state machine diagram in the narrative.
    public func transition(to newState: SessionState) {
        state = newState
    }

    // MARK: - Pool stats

    /// Replaces the pool-stats snapshot. Called by the 30-second heartbeat
    /// task and on every request completion.
    public func updatePoolStats(_ stats: PoolStats) {
        poolStats = stats
    }

    /// Returns the current pool-stats snapshot.
    public func currentPoolStats() -> PoolStats {
        poolStats
    }

    // MARK: - Registry mutations

    /// Registers a newly opened watch stream.
    public func registerWatchStream(_ ref: WatchStreamRef) {
        watchStreamRegistry.append(ref)
    }

    /// Removes a closed watch stream by its identifier.
    public func deregisterWatchStream(id: UUID) {
        watchStreamRegistry.removeAll { $0.id == id }
    }

    /// Registers a newly opened exec channel.
    public func registerExecSession(_ ref: ExecSessionRef) {
        execSessionRegistry.append(ref)
    }

    /// Removes a closed exec channel by its identifier.
    public func deregisterExecSession(id: UUID) {
        execSessionRegistry.removeAll { $0.id == id }
    }

    /// Registers a newly opened port-forward listener.
    public func registerPortForward(_ ref: PortForwardRef) {
        portForwardRegistry.append(ref)
    }

    /// Removes a closed port-forward listener by its identifier.
    public func deregisterPortForward(id: UUID) {
        portForwardRegistry.removeAll { $0.id == id }
    }

    /// Registers a newly opened terminal session.
    public func registerTerminalSession(_ ref: TerminalSessionRef) {
        terminalSessionRegistry.append(ref)
    }

    /// Removes a closed terminal session by its identifier.
    public func deregisterTerminalSession(id: UUID) {
        terminalSessionRegistry.removeAll { $0.id == id }
    }

    // MARK: - View state

    /// Replaces the per-cluster UI state snapshot.
    public func updateViewState(_ vs: ViewState) {
        viewState = vs
    }

    /// Returns the current per-cluster UI state snapshot.
    public func currentViewState() -> ViewState {
        viewState
    }

    // MARK: - Registry read access

    /// Returns a snapshot of all active watch streams.
    public func currentWatchStreamRegistry() -> [WatchStreamRef] {
        watchStreamRegistry
    }

    /// Returns a snapshot of all active exec channels.
    public func currentExecSessionRegistry() -> [ExecSessionRef] {
        execSessionRegistry
    }

    /// Returns a snapshot of all active port-forward listeners.
    public func currentPortForwardRegistry() -> [PortForwardRef] {
        portForwardRegistry
    }

    /// Returns a snapshot of all active terminal sessions.
    public func currentTerminalSessionRegistry() -> [TerminalSessionRef] {
        terminalSessionRegistry
    }
}
