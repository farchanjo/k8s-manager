# DDD role: BehaviouralSpecification
Feature: Menu bar tray energy management and application lifecycle
  As a K8sManager operator
  I want the tray to conserve energy when the system is constrained
  So that the application complies with macOS App Store efficiency guidelines

  Background:
    Given the application has launched successfully
    And the tray icon is installed in the menu bar
    And the active context is "staging"

  Scenario: Low power mode pauses the refresh scheduler
    Given refreshIntervalSeconds is 30
    And the refresh interval timer is active
    When the system low power mode is enabled (ProcessInfo.isLowPowerModeEnabled transitions to true)
    Then the TrayRefreshScheduler emits a RefreshPaused event with cause "low_power"
    And the interval timer publisher is cancelled
    And no outbound Prometheus queries are issued for the duration of low power mode
    And the tray icon does not change appearance solely due to the pause (appearance reflects last known cluster health)
    When the system low power mode is disabled
    Then the TrayRefreshScheduler emits a RefreshResumed event
    And the interval timer is reinstated with the same refreshIntervalSeconds value
    And a RefreshRequested with cause "interval" is emitted within one scheduler tick

  Scenario: backgroundRefreshEnabled false cancels subscriptions when popover closes
    Given the popover is open
    And backgroundRefreshEnabled is false
    And Combine subscriptions for all metric widgets are active
    When I close the popover
    Then the NSPopover delegate method popoverDidClose fires
    And the TrayPresenter cancels all entries in its AnyCancellable set
    And the interval timer subscription is cancelled
    And no outbound Prometheus queries are issued during a 60-second observation window after close
    And opening the popover again reinstates all subscriptions and triggers a RefreshRequested with cause "app_foreground"

  Scenario: backgroundRefreshEnabled true maintains polling at reduced rate when popover is closed
    Given the popover is open
    And backgroundRefreshEnabled is true
    And refreshIntervalSeconds is 30
    When I close the popover
    Then the interval timer subscription is retained after popoverDidClose
    And the effective background interval is 60 seconds (twice the configured interval)
    And outbound Prometheus queries are issued at the 60-second background interval
    And widget view models are updated in the background so that the popover shows current data when next opened
    And the tray icon iconState is updated in the background to reflect the latest cluster health

  Scenario: Network unreachable pauses refresh gracefully
    Given the refresh interval timer is active
    When the NWPathMonitor reports path status unsatisfied
    Then the TrayRefreshScheduler emits a RefreshPaused event with cause "network_unreachable"
    And any in-flight Prometheus query tasks are cancelled via URLSession task cancellation
    And no new queries are attempted while the network path remains unsatisfied
    And the tray icon displays the offline iconState appearance (reduced opacity)
    When the NWPathMonitor reports path status satisfied
    And no other pause conditions are active
    Then the TrayRefreshScheduler emits a RefreshResumed event
    And a RefreshRequested with cause "interval" is emitted
    And the tray icon iconState is recomputed from the first successful refresh result

  Scenario: Application quit removes the tray icon and cancels all queries
    Given the popover is closed
    And the interval timer is active
    When the operator selects "Quit K8sManager" from the Dock or the NSMenu
    Then the application delegates applicationWillTerminate fires
    And the TrayRefreshScheduler cancels all Combine subscriptions
    And any in-flight Prometheus queries are cancelled
    And the NSStatusItem is removed from the system status bar
    And the application terminates without leaving orphaned URLSession tasks
    And the MenuBarTray aggregate root state is persisted to local_persistence before termination
