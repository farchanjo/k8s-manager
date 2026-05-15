// DDD role: ValueObject
// Central codification of all measurable performance budgets for K8sManager.
// Individual bounded-context schemas reference these types to avoid
// duplicating ceiling values.  All ceilings in this file are invariants;
// relaxing any ceiling requires a new ADR.
//
// References:
//   ADR-0024 — Analytics Dashboard Bounded Context (dashboard query budget)
//   ADR-0025 — Per-Cluster Isolation Strategy (session memory)
//   ADR-0029 — kqueue I/O Event Selector (event-loop threads formula)
//   ADR-0030 — Integrated Editor (editor session memory)
//   ADR-0034 — State-Driven Realtime UI (frame budget)
//   ADR-0035 — Reactive Stack Integration (global RSS, stream buffer)
package _shared

// #FrameBudget defines the rendering frame-time ceiling.
// The targetMs value corresponds to the wall-clock budget for a single
// SwiftUI view body evaluation at 60 fps.
#FrameBudget: {
	targetMs: int & >=1 & <=16
}

// #ClusterSessionBudget defines resource ceilings for a single
// ClusterSessionActor including its event-loop group, kqueue FD,
// credential cache, watch buffers, and HTTPClient state.
//
// maxEventLoopThreads is derived per ADR-0029:
//   threads = min(processorCount, maxConcurrentWatches / 2)
// The formula is implemented in ClusterSessionActor; the field here
// records the upper bound for validation purposes only.
#ClusterSessionBudget: {
	maxMemoryMB:        int & >=1 & <=10
	maxConcurrentWatches: int & >=1 & <=16
	maxEventLoopThreads:  int & >=1
}

// #EditorSessionBudget defines ceilings for a single EditorSession
// (ADR-0030): content buffer + unsaved draft combined.
// Secret manifests MUST be redacted before draft persistence; the
// redacted form counts toward maxContentMB.
#EditorSessionBudget: {
	maxContentMB:              int & >=1 & <=1
	maxDryRunRequestsPer10Min: int & >=1 & <=60
}

// #PortForwardBudget defines ceilings for the port_forwarding bounded
// context at steady state.
// maxBytesPerSecondPerTunnel corresponds to 10 MiB/s per tunnel.
#PortForwardBudget: {
	maxConcurrentTunnels:         int & >=1 & <=8
	maxBytesPerSecondPerTunnel:   int & >=1 & <=10_485_760
}

// #TerminalSessionBudget defines ceilings for the terminal_session
// bounded context.
// maxBytesBufferedPerSession corresponds to 1 MiB per PTY buffer.
#TerminalSessionBudget: {
	maxConcurrentSessions:        int & >=1 & <=8
	maxBytesBufferedPerSession:   int & >=1 & <=1_048_576
}

// #AssistantChatBudget defines ceilings for the assistant_chat and
// llm_provider bounded contexts during a single streaming turn.
#AssistantChatBudget: {
	maxConcurrentToolInvocations:   int & >=1 & <=4
	maxTokensPerStreamingResponse:  int & >=1 & <=64000
}

// #DashboardBudget mirrors #WidgetBudget from the analytics_dashboard
// context so that the shared performance envelope can be validated
// centrally without importing the BC-specific package.
// The canonical definition lives in
// docs/arch/contexts/analytics_dashboard/schemas/widget_budget.cue.
#DashboardBudget: {
	maxPrometheusQueriesPerCycle: int & >=1 & <=5
	maxSimultaneousQueries:       int & >=1 & <=8
	refreshIntervalSeconds:       int & >=5 & <=60
	coalescingEnabled:            true
}

// #GlobalAppBudget defines process-level RSS ceilings measured by the
// self-monitoring surface (ADR-0027).
//
// baselineRssMB — idle state: 1 cluster connected, no dashboard open.
// loadedRssMB   — load state: 3 clusters, 5 active watches each,
//                 analytics dashboard open.
#GlobalAppBudget: {
	baselineRssMB: int & >=1 & <=200
	loadedRssMB:   int & >=1 & <=600
}

// _canonicalBudgets is a convenience value that assembles all budgets at
// their documented defaults.  Spec-pipeline tests unify against this
// value to detect accidental ceiling drift.
_canonicalBudgets: {
	frame: #FrameBudget & {
		targetMs: 16
	}
	clusterSession: #ClusterSessionBudget & {
		maxMemoryMB:          10
		maxConcurrentWatches: 16
		maxEventLoopThreads:  8
	}
	editorSession: #EditorSessionBudget & {
		maxContentMB:              1
		maxDryRunRequestsPer10Min: 60
	}
	portForward: #PortForwardBudget & {
		maxConcurrentTunnels:       8
		maxBytesPerSecondPerTunnel: 10_485_760
	}
	terminalSession: #TerminalSessionBudget & {
		maxConcurrentSessions:      8
		maxBytesBufferedPerSession: 1_048_576
	}
	assistantChat: #AssistantChatBudget & {
		maxConcurrentToolInvocations:  4
		maxTokensPerStreamingResponse: 64000
	}
	dashboard: #DashboardBudget & {
		maxPrometheusQueriesPerCycle: 5
		maxSimultaneousQueries:       8
		refreshIntervalSeconds:       30
		coalescingEnabled:            true
	}
	globalApp: #GlobalAppBudget & {
		baselineRssMB: 200
		loadedRssMB:   600
	}
}
