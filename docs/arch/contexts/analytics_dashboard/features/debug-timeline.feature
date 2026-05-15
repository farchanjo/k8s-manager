Feature: Debug Timeline Dashboard

  The Debug Timeline dashboard renders a unified, filterable, chronological
  event stream combining Kubernetes object events, mutation audit log entries,
  and assistant tool call invocations. It is used for post-mortem investigation
  of incidents that span multiple resource kinds and operator/assistant actions.
  The time range is adjustable and the stream supports per-source filtering,
  click-to-drill-down to a specific resource, and CSV export.

  Background:
    Given the operator has launched K8S-Manager
    And a Kubernetes context "production-aks" is selected and reachable
    And the operator has selected DebugTimelineScope in the sidebar

  Scenario: Unified event stream merges K8s events, mutation audit, and assistant tool calls in chronological order
    Given in the last 60 minutes:
      10 Kubernetes object events are recorded for various resources
      4 mutation audit entries exist (kubectl apply and patch operations)
      3 assistant tool call invocations are logged by cluster_intelligence
    When the "debug-unified-timeline" EventTimeline widget renders with sourceFilter = "all"
    Then 17 entries are displayed
    And they are ordered strictly by timestamp from oldest to newest
    And each entry shows its source icon: K8s event, mutation, or assistant call

  Scenario: Source filter limits displayed entries to a single stream
    Given the unified timeline has 10 k8s_events, 4 mutation_audit, and 3 assistant_tool_calls entries
    When the operator sets sourceFilter = "mutation_audit"
    Then exactly 4 entries are displayed
    And all displayed entries have source type "mutation_audit"
    And entries from "k8s_events" and "assistant_tool_calls" are not visible

  Scenario: Clicking an event entry drills down to the associated resource
    Given the debug timeline shows a mutation_audit entry at "2026-05-15T14:31:00Z" for Deployment "payments-api" in namespace "payments"
    When the operator clicks that timeline entry
    Then a DrillToScope event is emitted with targetScope = WorkloadDetailScope(kind="Deployment", namespace="payments", name="payments-api")
    And the sidebar scope picker switches to "Workload Detail"
    And the WorkloadDetail dashboard renders for that Deployment

  Scenario: Time range is adjustable with immediate re-query on change
    Given the DebugTimeline dashboard is displayed with timeRangeMinutes = 60
    When the operator selects "6h" from the range selector (timeRangeMinutes = 360)
    Then the timeRangeMinutes on the DebugTimelineScope updates to 360
    And all event sources are re-queried for the new 6-hour window
    And the unified timeline re-renders with the expanded data set within 3 seconds

  Scenario: Operator can export the debug timeline as CSV
    Given the debug timeline displays 45 entries spanning the last 60 minutes
    And the current filter is sourceFilter = "all"
    When the operator activates the "Export CSV" action in the timeline widget toolbar
    Then a CSV file named "debug-timeline-production-aks-2026-05-15T00-00-00Z.csv" is created
    And the CSV contains columns: timestamp, source, kind, namespace, name, message, operator
    And all 45 visible entries are included in the exported file
