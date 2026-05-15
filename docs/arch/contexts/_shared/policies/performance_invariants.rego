# DDD role: Policy
# Package: _shared.performance_invariants
#
# Validates a MetricsSample envelope (produced by the ADR-0027 self-monitoring
# surface) against the budget ceilings declared in
# docs/arch/contexts/_shared/schemas/performance_budgets.cue.
#
# Input shape (MetricsSample):
#   {
#     "rssMB": <number>,
#     "frameTimeMs": <number>,
#     "dashboardQueriesPerCycle": <number>,
#     "clusterSessions": [
#       { "id": "<string>", "memoryMB": <number>, "activeWatches": <number> }
#     ],
#     "editorSessions": [
#       { "id": "<string>", "contentMB": <number> }
#     ],
#     "portForwardTunnels": [
#       { "id": "<string>", "bytesPerSecond": <number> }
#     ],
#     "terminalSessions": [
#       { "id": "<string>", "bufferedBytes": <number> }
#     ]
#   }
#
# Default policy: deny.  A MetricsSample passes only when deny is empty.
#
# References:
#   ADR-0024 — Analytics Dashboard Bounded Context
#   ADR-0027 — App Self-Monitoring
#   ADR-0035 — Reactive Stack Integration
#   docs/arch/contexts/_shared/schemas/performance_budgets.cue

package _shared.performance_invariants

import future.keywords.every
import future.keywords.in
import future.keywords.contains
import future.keywords.if

# Default deny: every sample is rejected unless all rules pass.
default allow := false

allow if {
	count(deny) == 0
}

# ---------------------------------------------------------------------------
# Global RSS ceilings (ADR-0035 ### Memory ceilings, #GlobalAppBudget)
# ---------------------------------------------------------------------------

deny contains msg if {
	input.rssMB > 600
	msg := sprintf("global RSS over loaded ceiling: %d MB (limit 600 MB)", [input.rssMB])
}

deny contains msg if {
	# Baseline check applies only when the sample is tagged as an idle sample.
	input.sampleMode == "idle"
	input.rssMB > 200
	msg := sprintf("global RSS over baseline ceiling in idle mode: %d MB (limit 200 MB)", [input.rssMB])
}

# ---------------------------------------------------------------------------
# Per-ClusterSession memory ceiling (ADR-0035, #ClusterSessionBudget)
# ---------------------------------------------------------------------------

deny contains msg if {
	some session in input.clusterSessions
	session.memoryMB > 10
	msg := sprintf(
		"cluster session %q over memory ceiling: %d MB (limit 10 MB)",
		[session.id, session.memoryMB],
	)
}

# ---------------------------------------------------------------------------
# Per-ClusterSession concurrent watches ceiling (#ClusterSessionBudget)
# ---------------------------------------------------------------------------

deny contains msg if {
	some session in input.clusterSessions
	session.activeWatches > 16
	msg := sprintf(
		"cluster session %q exceeds concurrent watch limit: %d (limit 16)",
		[session.id, session.activeWatches],
	)
}

# ---------------------------------------------------------------------------
# Per-EditorSession content ceiling (#EditorSessionBudget)
# ---------------------------------------------------------------------------

deny contains msg if {
	some session in input.editorSessions
	session.contentMB > 1
	msg := sprintf(
		"editor session %q over content ceiling: %d MB (limit 1 MB)",
		[session.id, session.contentMB],
	)
}

# ---------------------------------------------------------------------------
# UI frame time ceiling (#FrameBudget, ADR-0034 / ADR-0035)
# ---------------------------------------------------------------------------

deny contains msg if {
	input.frameTimeMs > 16
	msg := sprintf("frame budget exceeded: %.2f ms (limit 16 ms)", [input.frameTimeMs])
}

# ---------------------------------------------------------------------------
# Dashboard query budget (ADR-0024 ### Query budget invariant, #DashboardBudget)
# ---------------------------------------------------------------------------

deny contains msg if {
	input.dashboardQueriesPerCycle > 5
	msg := sprintf(
		"dashboard query budget exceeded: %d queries per cycle (limit 5)",
		[input.dashboardQueriesPerCycle],
	)
}

# ---------------------------------------------------------------------------
# Port-forward per-tunnel bandwidth ceiling (#PortForwardBudget)
# ---------------------------------------------------------------------------

deny contains msg if {
	some tunnel in input.portForwardTunnels
	tunnel.bytesPerSecond > 10485760
	msg := sprintf(
		"port-forward tunnel %q over bandwidth ceiling: %d B/s (limit 10 MiB/s)",
		[tunnel.id, tunnel.bytesPerSecond],
	)
}

# ---------------------------------------------------------------------------
# Terminal session buffer ceiling (#TerminalSessionBudget)
# ---------------------------------------------------------------------------

deny contains msg if {
	some session in input.terminalSessions
	session.bufferedBytes > 1048576
	msg := sprintf(
		"terminal session %q over buffer ceiling: %d bytes (limit 1 MiB)",
		[session.id, session.bufferedBytes],
	)
}

# ---------------------------------------------------------------------------
# Negative test cases (OPA test suite — run with `opa test .`)
# ---------------------------------------------------------------------------

# test_allow_healthy_sample verifies that a sample within all ceilings passes.
test_allow_healthy_sample if {
	allow with input as {
		"rssMB":                    150,
		"frameTimeMs":              12.5,
		"dashboardQueriesPerCycle": 4,
		"sampleMode":               "idle",
		"clusterSessions": [
			{"id": "cluster-a", "memoryMB": 8, "activeWatches": 10},
		],
		"editorSessions": [
			{"id": "editor-1", "contentMB": 0},
		],
		"portForwardTunnels": [
			{"id": "tunnel-1", "bytesPerSecond": 5000000},
		],
		"terminalSessions": [
			{"id": "term-1", "bufferedBytes": 512000},
		],
	}
}

# test_deny_rss_over_loaded_ceiling verifies that 601 MB RSS triggers a deny.
test_deny_rss_over_loaded_ceiling if {
	count(deny) > 0 with input as {
		"rssMB":                    601,
		"frameTimeMs":              10,
		"dashboardQueriesPerCycle": 3,
		"clusterSessions":          [],
		"editorSessions":           [],
		"portForwardTunnels":       [],
		"terminalSessions":         [],
	}
}

# test_deny_rss_over_baseline_ceiling verifies that 201 MB in idle mode triggers a deny.
test_deny_rss_over_baseline_ceiling if {
	count(deny) > 0 with input as {
		"rssMB":                    201,
		"frameTimeMs":              10,
		"dashboardQueriesPerCycle": 2,
		"sampleMode":               "idle",
		"clusterSessions":          [],
		"editorSessions":           [],
		"portForwardTunnels":       [],
		"terminalSessions":         [],
	}
}

# test_deny_cluster_session_over_memory verifies the per-session ceiling.
test_deny_cluster_session_over_memory if {
	count(deny) > 0 with input as {
		"rssMB":                    100,
		"frameTimeMs":              8,
		"dashboardQueriesPerCycle": 2,
		"clusterSessions": [
			{"id": "cluster-x", "memoryMB": 11, "activeWatches": 5},
		],
		"editorSessions":     [],
		"portForwardTunnels": [],
		"terminalSessions":   [],
	}
}

# test_deny_frame_budget_exceeded verifies the 16 ms frame ceiling.
test_deny_frame_budget_exceeded if {
	count(deny) > 0 with input as {
		"rssMB":                    100,
		"frameTimeMs":              17,
		"dashboardQueriesPerCycle": 3,
		"clusterSessions":          [],
		"editorSessions":           [],
		"portForwardTunnels":       [],
		"terminalSessions":         [],
	}
}

# test_deny_dashboard_query_budget_exceeded verifies the 5-query ceiling.
test_deny_dashboard_query_budget_exceeded if {
	count(deny) > 0 with input as {
		"rssMB":                    100,
		"frameTimeMs":              10,
		"dashboardQueriesPerCycle": 6,
		"clusterSessions":          [],
		"editorSessions":           [],
		"portForwardTunnels":       [],
		"terminalSessions":         [],
	}
}
