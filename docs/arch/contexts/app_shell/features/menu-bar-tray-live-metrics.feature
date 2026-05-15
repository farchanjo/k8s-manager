Feature: Menu bar tray live metrics
  As a K8sManager operator
  I want live cluster metrics displayed in the tray popover
  So that I can see CPU, memory, pod counts, and recent changes at a glance

  Background:
    Given the application has launched successfully
    And the active context is "staging"
    And Prometheus is configured and reachable for "staging"
    And the popover is open

  Scenario: CPU sparkline renders after the first Prometheus sample arrives
    Given the TrayLayout includes the widget "cpu-usage" of kind "sparkline"
    And the promQLTemplate for "cpu-usage" is a valid cluster-wide CPU expression
    When the TrayRefreshScheduler emits a RefreshRequested with cause "app_foreground"
    Then the metrics_observability PromQueryAdapter issues a query_range request to Prometheus
    And Prometheus returns a matrix with 60 data points over the last 60 minutes
    And the TrayPresenter updates the "cpu-usage" widget with the received samples
    And the popover renders a line chart for "cpu-usage" using Swift Charts LineMark
    And the chart tooltip for the most recent sample shows a value formatted as a percentage
    And the VoiceOver accessibility label for the sparkline includes the current percentage value

  Scenario: Refresh interval of 30 seconds re-queries Prometheus automatically
    Given refreshIntervalSeconds is 30
    And manualRefreshOnly is false
    When 30 seconds elapse since the last successful refresh
    Then the TrayRefreshScheduler emits a RefreshRequested with cause "interval"
    And the TrayPresenter issues new PromQL queries for all metric widgets
    And the lastRefreshedAtRFC3339 field on MenuBarTray is updated to the current UTC time
    And the "last checked X ago" timestamp in the popover header resets to "just now"

  Scenario: Manual refresh button forces an immediate query
    Given the interval timer has 25 seconds remaining before the next scheduled refresh
    When I press the refresh button in the quick actions toolbar
    Then the TrayRefreshScheduler emits a RefreshRequested with cause "manual"
    And the TrayPresenter begins querying all widgets immediately without waiting for the timer
    And the interval timer resets after the manual refresh completes
    And the popover displays a loading indicator during the in-flight queries

  Scenario: Prometheus not configured shows empty state with settings link
    Given Prometheus is not configured for the active context
    When the TrayRefreshScheduler completes a refresh cycle
    Then the four sparkline and stacked-bar metric widgets are replaced by a single empty-state view
    And the empty-state view displays the message "Install Prometheus stack"
    And the empty-state view contains a button that opens Settings at the Prometheus configuration section
    And the counts widgets remain visible because they are sourced from the Kubernetes API
    And the recent mutations widget remains visible because it is sourced from MutationAuditReadModel

  Scenario: Lid closed pauses refresh and opening the lid resumes it
    Given the refresh interval is active
    And the system screen sleep notification fires (lid closed equivalent)
    Then the TrayRefreshScheduler emits a RefreshPaused event with cause "lid_closed"
    And no Prometheus queries are issued while the lid is closed
    And the popover quick actions toolbar shows a "Paused" indicator if the popover is open
    When the system wake-from-sleep notification fires (lid opened)
    Then the TrayRefreshScheduler emits a RefreshResumed event
    And a RefreshRequested with cause "interval" is emitted within one scheduler tick
    And Prometheus queries resume normally

  Scenario: Refresh failure with 429 response marks the widget as degraded
    Given the refresh interval is active
    When Prometheus returns HTTP 429 Too Many Requests for the "cpu-usage" widget query
    Then the TrayPresenter emits a RefreshFailed event with reason "rate_limited" and widgetId "cpu-usage"
    And the "cpu-usage" sparkline widget displays a degraded orange badge
    And the last successfully fetched data remains visible under the badge
    And the VoiceOver accessibility value for the widget announces "cpu-usage: data unavailable, rate limited"
    And the next scheduled interval retry does not increase the query rate beyond one request per refreshIntervalSeconds

  Scenario: Recent mutations widget shows the last 5 operations with outcome icons
    Given the resource_browser MutationAuditReadModel contains at least 5 recent operations for "staging"
    When the TrayPresenter reads MutationAuditReadModel with limit 5
    Then the recent mutations widget renders 5 rows
    And each row displays a relative timestamp, the operation verb, the resource kind and name
    And rows with a successful outcome display a checkmark circle icon using statusHealthy colour
    And rows with a failed outcome display an xmark circle icon using statusError colour
    And the widget title displays "Recent changes"
    And the VoiceOver accessibility label for each row includes verb, kind, name, and outcome description

  Scenario: Network rate dual-line sparkline shows rx and tx simultaneously
    Given the TrayLayout includes the widget "network-io" rendered as a dual-line composition
    And the promQLTemplate for the rx series and the tx series are both valid expressions
    When the TrayPresenter receives sample data for both rx and tx series
    Then the popover renders a single Swift Charts view with two LineMark series
    And the rx series is visually distinguished from the tx series using foregroundStyle
    And the chart legend labels the two series "rx" and "tx"
    And tooltip values for both series are formatted with SI prefix and "/s" suffix
