// DDD role: ValueObject
// Enforces the query budget invariants declared in ADR-0024
// (### Query budget invariant).  Every #Dashboard value-object MUST embed
// a #WidgetBudget and the spec pipeline validates all constraints below
// before accepting a dashboard configuration.
//
// References:
//   ADR-0024 — Analytics Dashboard Bounded Context
//   docs/arch/contexts/_shared/schemas/performance_budgets.cue (#DashboardBudget)
package analytics_dashboard

#WidgetBudget: {
	// Maximum number of distinct Prometheus range queries issued per
	// refresh cycle per dashboard scope.  Distinct identity is defined by
	// the tuple (promQLTemplate, rangeMinutes, scopeParameters).
	// Widget-level coalescing is mandatory: widgets sharing a PromQL
	// template prefix MUST be merged before dispatch.
	maxPrometheusQueriesPerCycle: int & >=1 & <=5

	// Maximum number of simultaneous in-flight queries across all data
	// sources (Prometheus range queries + Kubernetes API list/get calls)
	// for a single scope at any point during a refresh cycle.
	maxSimultaneousQueries: int & >=1 & <=8

	// Refresh interval in seconds.  Lower bound prevents Prometheus query
	// storms; upper bound is the energy-saver ceiling.  Default is 30 s;
	// energy-saver mode MUST use at least 60 s.
	refreshIntervalSeconds: int & >=5 & <=60

	// Widget-level PromQL prefix coalescing is not optional.
	// This field MUST always be true; a false value is a spec error.
	coalescingEnabled: true
}

// _defaultWidgetBudget is the canonical baseline used by scope presets that
// do not need to override individual fields.
_defaultWidgetBudget: #WidgetBudget & {
	maxPrometheusQueriesPerCycle: 5
	maxSimultaneousQueries:       8
	refreshIntervalSeconds:       30
	coalescingEnabled:            true
}
