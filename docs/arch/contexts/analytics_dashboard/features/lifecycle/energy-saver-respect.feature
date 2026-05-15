# DDD role: BehaviouralSpecification
# Bounded context: analytics_dashboard
# References: ADR-0022, ADR-0024, ADR-0029

Feature: Energy-saver mode extends dashboard refresh interval
  As an operator on a MacBook
  I want dashboard refresh to slow down when the system enters low-power mode
  So that K8sManager does not drain battery when the operator is not actively monitoring

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And the ClusterOverview dashboard refresh interval is 30 seconds (default)

  @happy @lifecycle
  Scenario: System enters low-power mode — refresh interval extends to 60 seconds
    When macOS signals low-power mode (NSProcessInfo.isLowPowerModeEnabled becomes true)
    Then the menu bar tray emits a TrayRefreshEvent with energySaverActive=true
    And the PrometheusQueryActor receives the event and sets its refresh interval to 60 seconds
    And the next refresh fires at T+60s (not T+30s)
    And the dashboard header shows a battery-saver indicator

  @happy @lifecycle
  Scenario: System exits low-power mode — refresh interval returns to 30 seconds
    Given low-power mode is active and the refresh interval is 60 seconds
    When NSProcessInfo.isLowPowerModeEnabled becomes false
    Then the menu bar tray emits a TrayRefreshEvent with energySaverActive=false
    And the PrometheusQueryActor resets its refresh interval to 30 seconds
    And the dashboard header hides the battery-saver indicator
    And the next refresh fires at T+30s

  @failure @lifecycle
  Scenario: kqueue EVFILT_TIMER rearms after energy-saver interval change
    Given the kqueue EVFILT_TIMER is armed with a 30-second interval
    When low-power mode is detected
    Then the existing EVFILT_TIMER registration is cancelled
    And a new EVFILT_TIMER is registered with a 60-second interval
    And no missed refresh cycles occur during the rearm operation

  @happy @lifecycle
  Scenario: Menu bar tray also respects energy-saver and stops polling live metrics
    Given the menu bar tray was polling live CPU and memory metrics every 5 seconds
    When low-power mode is detected
    Then the menu bar tray suspends its metric polling
    And the last known metric values are frozen in the tray display
    And polling resumes at normal cadence when low-power mode ends
