# DDD role: Policy
package analytics_dashboard.dashboard_policy

# dashboard_policy.rego
#
# Governs analytics widget queries: enforces query budgets per refresh
# cycle, rejects unbounded PromQL label matchers, and respects macOS
# energy-saver constraints surfaced by the menu bar tray.
#
# input.queriesThisCycle     — int: number of queries already issued in
#                              the current refresh cycle
# input.queryBudget          — int: max queries allowed per refresh cycle
#                              (operator-configurable; default 20)
# input.promQL               — string: the PromQL expression being evaluated
# input.energySaverActive    — bool: macOS Low Power Mode or battery-saving
#                              constraint is active
# input.widgetId             — string: the dashboard widget identifier

default allow := false

# ---------------------------------------------------------------------------
# Happy-path allow: within budget, PromQL safe, no energy-saver block
# ---------------------------------------------------------------------------

allow {
    input.queriesThisCycle < input.queryBudget
    not promql_has_unbounded_matcher(input.promQL)
    not input.energySaverActive
}

# Allow under energy-saver only for critical/system widgets.
# Operator marks a widget as critical via the dashboard settings.
allow {
    input.queriesThisCycle < input.queryBudget
    not promql_has_unbounded_matcher(input.promQL)
    input.energySaverActive == true
    input.widgetCritical == true
}

# ---------------------------------------------------------------------------
# PromQL safety check
# An unbounded label matcher is one that uses a regex match operator (=~)
# with a pattern that begins with .* or is simply .*, allowing label values
# to enumerate all cardinality. Exact and prefix-bounded matchers are safe.
# ---------------------------------------------------------------------------

promql_has_unbounded_matcher(expr) {
    contains(expr, `=~".*"`)
}

promql_has_unbounded_matcher(expr) {
    contains(expr, "=~'.*'")
}

promql_has_unbounded_matcher(expr) {
    contains(expr, `{}"`)
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_query_budget_exceeded[msg] {
    input.queriesThisCycle >= input.queryBudget
    msg := sprintf(
        "widget %q query denied: %d queries have been issued this refresh cycle, exceeding the budget of %d; reduce widget count or increase the refresh interval",
        [input.widgetId, input.queriesThisCycle, input.queryBudget]
    )
}

deny_unbounded_promql_matcher[msg] {
    promql_has_unbounded_matcher(input.promQL)
    msg := sprintf(
        "widget %q query denied: PromQL expression contains an unbounded label matcher (=~\".*\"); use a specific label value or prefix-bounded regex",
        [input.widgetId]
    )
}

deny_energy_saver_non_critical[msg] {
    input.energySaverActive == true
    input.widgetCritical == false
    msg := sprintf(
        "widget %q query denied: macOS energy-saver constraint is active; only widgets marked as critical are permitted to query during low-power mode",
        [input.widgetId]
    )
}

# ---------------------------------------------------------------------------
# Negative test cases
#
# test_deny_query_budget_exceeded:
#   input = {
#     "queriesThisCycle": 20, "queryBudget": 20,
#     "promQL": "up",
#     "energySaverActive": false, "widgetCritical": false,
#     "widgetId": "cluster-health"
#   }
#   expect: allow == false
#   expect: deny_query_budget_exceeded contains "exceeding the budget"
#
# test_deny_unbounded_promql:
#   input = {
#     "queriesThisCycle": 0, "queryBudget": 20,
#     "promQL": "http_requests_total{method=~\".*\"}",
#     "energySaverActive": false, "widgetCritical": false,
#     "widgetId": "requests-widget"
#   }
#   expect: allow == false
#   expect: deny_unbounded_promql_matcher contains "unbounded label matcher"
#
# test_deny_energy_saver_non_critical:
#   input = {
#     "queriesThisCycle": 0, "queryBudget": 20,
#     "promQL": "up",
#     "energySaverActive": true, "widgetCritical": false,
#     "widgetId": "latency-heatmap"
#   }
#   expect: allow == false
#   expect: deny_energy_saver_non_critical contains "energy-saver constraint"
# ---------------------------------------------------------------------------
