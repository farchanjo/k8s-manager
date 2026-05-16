// Budgets.swift — performance budget value objects
// Bounded context: shared_kernel
// Spec:           docs/arch/contexts/_shared/schemas/performance_budgets.cue
// Decisions:      ADR-0024, ADR-0025, ADR-0029, ADR-0030, ADR-0034, ADR-0035
//
// Each struct mirrors the corresponding CUE schema type exactly.
// All values are `let` (immutable value semantics); the canonical defaults
// from `_canonicalBudgets` in the CUE file are expressed as static properties.
// Ceiling enforcement at runtime is the responsibility of individual bounded
// context actors; this file records the invariants only.

// MARK: - FrameBudget

/// Rendering frame-time ceiling.
///
/// `targetMs` is the wall-clock budget for a single SwiftUI view-body evaluation
/// at 60 fps. Clamped by CUE to `1...16` ms.
public struct FrameBudget: Sendable, Codable, Hashable {
    /// Maximum acceptable frame render time in milliseconds (1–16).
    public let targetMs: Int

    public init(targetMs: Int) {
        self.targetMs = targetMs
    }

    /// Canonical default: 16 ms (60 fps). Source: `_canonicalBudgets.frame`.
    public static let canonical = FrameBudget(targetMs: 16)
}

// MARK: - GlobalAppBudget

/// Process-level RSS ceilings measured by the self-monitoring surface (ADR-0027).
///
/// `baselineRssMB` — idle state: one cluster connected, no dashboard open.
/// `loadedRssMB`   — load state: three clusters, five active watches each,
///                   analytics dashboard open.
public struct GlobalAppBudget: Sendable, Codable, Hashable {
    /// RSS ceiling in the idle baseline state (1–200 MB).
    public let baselineRssMB: Int
    /// RSS ceiling under representative load (1–600 MB).
    public let loadedRssMB: Int

    public init(baselineRssMB: Int, loadedRssMB: Int) {
        self.baselineRssMB = baselineRssMB
        self.loadedRssMB = loadedRssMB
    }

    /// Canonical default: 200 MB baseline / 600 MB loaded.
    public static let canonical = GlobalAppBudget(baselineRssMB: 200, loadedRssMB: 600)
}

// MARK: - WidgetQueryBudget (DashboardBudget)

/// Dashboard widget query budget.
///
/// Mirrors `#DashboardBudget` in `performance_budgets.cue`. The canonical definition
/// lives in `analytics_dashboard/schemas/widget_budget.cue`; this copy allows
/// cross-context validation without importing BC-specific packages.
public struct WidgetQueryBudget: Sendable, Codable, Hashable {
    /// Maximum Prometheus queries per refresh cycle (1–5).
    public let maxPrometheusQueriesPerCycle: Int
    /// Maximum simultaneous in-flight Prometheus queries (1–8).
    public let maxSimultaneousQueries: Int
    /// Dashboard refresh interval in seconds (5–60).
    public let refreshIntervalSeconds: Int
    /// Coalescing must always be enabled; this field is invariantly `true`.
    public let coalescingEnabled: Bool

    public init(
        maxPrometheusQueriesPerCycle: Int,
        maxSimultaneousQueries: Int,
        refreshIntervalSeconds: Int,
        coalescingEnabled: Bool
    ) {
        self.maxPrometheusQueriesPerCycle = maxPrometheusQueriesPerCycle
        self.maxSimultaneousQueries = maxSimultaneousQueries
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.coalescingEnabled = coalescingEnabled
    }

    /// Canonical default: 5 queries/cycle, 8 concurrent, 30 s refresh.
    public static let canonical = WidgetQueryBudget(
        maxPrometheusQueriesPerCycle: 5,
        maxSimultaneousQueries: 8,
        refreshIntervalSeconds: 30,
        coalescingEnabled: true
    )
}

// MARK: - WatchStreamBudget (ClusterSessionBudget)

/// Resource ceilings for a single `ClusterSessionActor`.
///
/// Mirrors `#ClusterSessionBudget` in `performance_budgets.cue`.
/// `maxEventLoopThreads` is derived per ADR-0029:
/// `threads = min(processorCount, maxConcurrentWatches / 2)`;
/// the field here records the upper bound for validation only.
public struct WatchStreamBudget: Sendable, Codable, Hashable {
    /// Maximum per-session RSS in MB (1–10).
    public let maxMemoryMB: Int
    /// Maximum concurrent Kubernetes API watch streams per session (1–16).
    public let maxConcurrentWatches: Int
    /// Upper bound on kqueue event-loop threads (≥1).
    public let maxEventLoopThreads: Int

    public init(maxMemoryMB: Int, maxConcurrentWatches: Int, maxEventLoopThreads: Int) {
        self.maxMemoryMB = maxMemoryMB
        self.maxConcurrentWatches = maxConcurrentWatches
        self.maxEventLoopThreads = maxEventLoopThreads
    }

    /// Canonical default: 10 MB, 16 watches, 8 threads.
    public static let canonical = WatchStreamBudget(
        maxMemoryMB: 10,
        maxConcurrentWatches: 16,
        maxEventLoopThreads: 8
    )
}

// MARK: - MutationLatencyBudget (EditorSessionBudget)

/// Ceilings for a single editor session (ADR-0030).
///
/// Mirrors `#EditorSessionBudget` in `performance_budgets.cue`.
/// Content buffer + unsaved draft combined count toward `maxContentMB`.
/// Secret manifests must be redacted before draft persistence; the redacted form
/// still counts against the ceiling.
public struct MutationLatencyBudget: Sendable, Codable, Hashable {
    /// Maximum combined content + draft size in MB (1–1).
    public let maxContentMB: Int
    /// Maximum dry-run API requests per 10-minute sliding window (1–60).
    public let maxDryRunRequestsPer10Min: Int

    public init(maxContentMB: Int, maxDryRunRequestsPer10Min: Int) {
        self.maxContentMB = maxContentMB
        self.maxDryRunRequestsPer10Min = maxDryRunRequestsPer10Min
    }

    /// Canonical default: 1 MB content, 60 dry-run requests per 10 min.
    public static let canonical = MutationLatencyBudget(
        maxContentMB: 1,
        maxDryRunRequestsPer10Min: 60
    )
}

// MARK: - LLMTokenBudget (AssistantChatBudget)

/// Ceilings for the `assistant_chat` and `llm_provider` bounded contexts during a
/// single streaming turn.
///
/// Mirrors `#AssistantChatBudget` in `performance_budgets.cue`.
public struct LLMTokenBudget: Sendable, Codable, Hashable {
    /// Maximum concurrent MCP tool invocations per streaming turn (1–4).
    public let maxConcurrentToolInvocations: Int
    /// Maximum output tokens per streaming response (1–64 000).
    public let maxTokensPerStreamingResponse: Int

    public init(maxConcurrentToolInvocations: Int, maxTokensPerStreamingResponse: Int) {
        self.maxConcurrentToolInvocations = maxConcurrentToolInvocations
        self.maxTokensPerStreamingResponse = maxTokensPerStreamingResponse
    }

    /// Canonical default: 4 concurrent tools, 64 000 tokens.
    public static let canonical = LLMTokenBudget(
        maxConcurrentToolInvocations: 4,
        maxTokensPerStreamingResponse: 64_000
    )
}

// MARK: - MCPInvocationBudget (TerminalSessionBudget)

/// Ceilings for the `terminal_session` bounded context.
///
/// Mirrors `#TerminalSessionBudget` in `performance_budgets.cue`.
public struct MCPInvocationBudget: Sendable, Codable, Hashable {
    /// Maximum concurrent PTY exec sessions (1–8).
    public let maxConcurrentSessions: Int
    /// Maximum bytes buffered per PTY session before oldest bytes are evicted (1–1 048 576).
    public let maxBytesBufferedPerSession: Int

    public init(maxConcurrentSessions: Int, maxBytesBufferedPerSession: Int) {
        self.maxConcurrentSessions = maxConcurrentSessions
        self.maxBytesBufferedPerSession = maxBytesBufferedPerSession
    }

    /// Canonical default: 8 sessions, 1 MiB buffer.
    public static let canonical = MCPInvocationBudget(
        maxConcurrentSessions: 8,
        maxBytesBufferedPerSession: 1_048_576
    )
}

// MARK: - PortForwardLatencyBudget (PortForwardBudget)

/// Ceilings for the `port_forwarding` bounded context at steady state.
///
/// Mirrors `#PortForwardBudget` in `performance_budgets.cue`.
/// `maxBytesPerSecondPerTunnel` corresponds to 10 MiB/s per tunnel.
public struct PortForwardLatencyBudget: Sendable, Codable, Hashable {
    /// Maximum concurrent TCP tunnels across all active sessions (1–8).
    public let maxConcurrentTunnels: Int
    /// Throughput ceiling per tunnel in bytes per second (1–10 485 760).
    public let maxBytesPerSecondPerTunnel: Int

    public init(maxConcurrentTunnels: Int, maxBytesPerSecondPerTunnel: Int) {
        self.maxConcurrentTunnels = maxConcurrentTunnels
        self.maxBytesPerSecondPerTunnel = maxBytesPerSecondPerTunnel
    }

    /// Canonical default: 8 tunnels, 10 MiB/s per tunnel.
    public static let canonical = PortForwardLatencyBudget(
        maxConcurrentTunnels: 8,
        maxBytesPerSecondPerTunnel: 10_485_760
    )
}
