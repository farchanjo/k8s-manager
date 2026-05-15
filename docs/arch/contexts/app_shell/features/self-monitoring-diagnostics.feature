# DDD role: BehaviouralSpecification
Feature: App self-monitoring diagnostics
  As an operator running K8sManager on macOS
  I want live visibility into the application's own resource usage
  So that I can detect performance regressions and session leaks without external tooling

  Background:
    Given K8sManager is running and has completed cold-start initialization
    And the SelfMonitoringSampler is active with a 5-second sample interval
    And Settings → Diagnostics is open

  # ---------------------------------------------------------------------------
  # Scenario 1 — Live counters refresh on every sample
  # ---------------------------------------------------------------------------

  Scenario: Live counters update on every sample interval
    Given the SelfMonitoringSampler has collected at least 2 samples
    When 5 seconds elapse after the last sample
    Then the Settings → Diagnostics live counter grid refreshes within 1 second
    And the displayed "CPU %" value differs from the previous value when CPU usage changed
    And the displayed "Memory RSS" value reflects the current phys_footprint reading
    And the displayed "Active watch streams" count matches the number of open watch connections

  # ---------------------------------------------------------------------------
  # Scenario 2 — Sparklines show last 60 minutes
  # ---------------------------------------------------------------------------

  Scenario: CPU and memory sparklines retain 60 minutes of history
    Given the SelfMonitoringSampler has been running for at least 60 minutes
    When the operator opens Settings → Diagnostics
    Then the CPU sparkline contains exactly 720 data points (60 min ÷ 5 s)
    And the memory RSS sparkline contains exactly 720 data points
    And the network in/out sparkline contains exactly 720 data points
    And the oldest visible data point is approximately 60 minutes old
    And no data points older than 60 minutes are shown

  # ---------------------------------------------------------------------------
  # Scenario 3 — Tray widget surface is opt-in and off by default
  # ---------------------------------------------------------------------------

  Scenario: Menu bar tray widget is hidden unless operator opts in
    Given the operator has never enabled "Show app health in menu bar"
    When the operator opens the menu bar tray popover
    Then no "App self-monitoring" widget is visible in the popover
    When the operator enables "Show app health in menu bar" in Settings → Diagnostics
    And the operator opens the menu bar tray popover again
    Then a compact "App self-monitoring" chip row is visible showing CPU %, memory MB, and active session counts
    When the operator disables "Show app health in menu bar"
    And the operator opens the menu bar tray popover again
    Then no "App self-monitoring" widget is visible

  # ---------------------------------------------------------------------------
  # Scenario 4 — Active session counter reflects live cluster sessions
  # ---------------------------------------------------------------------------

  Scenario: Active watch streams counter reflects open Kubernetes watch connections
    Given the operator has 2 cluster sessions connected
    And each session has 3 active watch streams
    When the SelfMonitoringSampler collects the next sample
    Then the "Active watch streams" counter in Settings → Diagnostics shows 6
    When 1 cluster session disconnects and its 3 watch streams close
    And the SelfMonitoringSampler collects the next sample
    Then the "Active watch streams" counter shows 3
    And the "Event loop group count" counter decreases by 1

  # ---------------------------------------------------------------------------
  # Scenario 5 — Sample interval reconfiguration takes effect immediately
  # ---------------------------------------------------------------------------

  Scenario: Operator reconfigures sample interval and sampler adapts
    Given the current sample interval is 5 seconds
    When the operator selects "1 second" in the sample interval selector in Settings → Diagnostics
    Then the SelfMonitoringSampler schedules the next sample within 1 second
    And subsequent samples arrive at approximately 1-second intervals
    When the operator selects "60 seconds"
    Then the SelfMonitoringSampler schedules the next sample within 60 seconds
    And the ring buffer retention size adjusts to accommodate 60 minutes at the new interval

  # ---------------------------------------------------------------------------
  # Scenario 6 — CPU and memory sanity checks on collected samples
  # ---------------------------------------------------------------------------

  Scenario: Collected metric values are within valid physical bounds
    When the SelfMonitoringSampler collects a sample
    Then cpuUsagePercent is between 0.0 and (100.0 × the number of logical CPU cores)
    And memoryRSSBytes is greater than 0
    And memoryPeakRSSBytes is greater than or equal to memoryRSSBytes
    And threadCount is greater than 0
    And activeWatchStreams is greater than or equal to 0
    And activeExecSessions is greater than or equal to 0
    And activePortForwards is greater than or equal to 0
    And activeChatStreams is greater than or equal to 0
    And networkBytesIn is greater than or equal to 0
    And networkBytesOut is greater than or equal to 0

  # ---------------------------------------------------------------------------
  # Scenario 7 — Unavailable sandbox metrics degrade gracefully
  # ---------------------------------------------------------------------------

  Scenario: Metrics unavailable in App Sandbox are reported as sentinel -1
    Given the application is running inside an App Sandbox
    And proc_pidinfo(PROC_PIDLISTFDS) returns an error for the process PID
    When the SelfMonitoringSampler collects a sample
    Then the fileDescriptorCount field in the sample equals -1
    And the Settings → Diagnostics counter for "File descriptors" displays "unavailable"
    And no error dialog or crash occurs
    And all other fields that are available still contain valid non-sentinel values
