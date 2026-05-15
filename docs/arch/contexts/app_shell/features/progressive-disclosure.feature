# DDD role: Feature
# Bounded context: app_shell
Feature: Progressive disclosure of resource detail and advanced controls

  As a Kubernetes operator on macOS
  I want resource information revealed in three deliberate layers
  So that the overview canvas stays clean while full detail and config remain immediately reachable

  Background:
    Given the application is running with at least one cluster connected
    And the resource browser is visible with a list of Deployment resources
    And power-user mode is disabled in settings

  Scenario: Layer 1 overview shows aggregate health KPIs without interaction
    When the operator views the resource browser list
    Then each Deployment row shows ready replica count
    And each Deployment row shows restart count
    And each Deployment row shows resource age
    And each Deployment row shows a color-coded status indicator using the five-color semantic scheme
    And no event stream, condition table, or YAML content is visible
    And the list renders within 200 milliseconds of the namespace switch completing

  Scenario: Clicking a resource row reveals the Layer 2 detail panel
    Given the resource browser shows at least one Deployment row
    When the operator clicks the Deployment row
    Then the detail panel slides into view
    And the detail panel shows the Events tab with recent resource events
    And the detail panel shows the Conditions tab with status conditions
    And the detail panel shows the RED method metrics panel
    And the RED method panel has request rate and error rate in the left column
    And the RED method panel has latency percentiles p50, p95, and p99 in the right column
    And clicking a spike in the request rate chart navigates to the log stream at that timestamp

  Scenario: Pressing Enter on a focused resource row also reveals the Layer 2 detail panel
    Given a Deployment resource row is focused in the resource browser
    When the operator presses Enter
    Then the Layer 2 detail panel opens for that Deployment
    And the detail panel has keyboard focus

  Scenario: Opening YAML editor advances to Layer 3 from Layer 2
    Given the Layer 2 detail panel is open for a Deployment
    When the operator presses the "e" key or Cmd-E
    Then the YAML editor pane opens within the detail panel
    And the raw YAML content of the Deployment is displayed and editable
    And the Layer 2 summary tabs are hidden while the YAML editor is active
    And Escape closes the YAML editor and returns to the Layer 2 detail panel

  Scenario: Enabling power-user mode collapses disclosure layers into a dense list
    Given power-user mode is disabled
    When the operator enables power-user mode in settings
    Then the resource browser list switches to a dense single-line row format
    And the Layer 2 detail panel is not shown automatically on row selection
    And more resources are visible per screen without scrolling
    When the operator disables power-user mode
    Then the resource browser list returns to the standard three-layer disclosure format

  Scenario: Advanced controls in the detail panel are gated behind a deliberate action
    Given the Layer 2 detail panel is open for a Deployment
    When the operator views the detail panel without any further interaction
    Then scale controls, rollout actions, and environment variable overrides are not visible
    When the operator clicks the "Advanced" disclosure group
    Then the scale input, rollout restart button, and environment variable section expand
    And the advanced controls section is announced to VoiceOver as expanded

  Scenario: Sidebar lazy-reveal shows only top-level resource kinds on cold start
    Given the application is launching for the first time in a session
    When the sidebar finishes loading
    Then only the top-level resource kind groups are shown in the sidebar
    And child resource kinds within each group are not yet fetched or rendered
    When the operator expands a resource kind group
    Then the child resource kinds for that group are fetched from the API server
    And they appear in the sidebar within 500 milliseconds

  Scenario: Reduce-motion preference suppresses detail panel slide animation
    Given the macOS system preference for reduce motion is enabled
    When the operator clicks a resource row to open the Layer 2 detail panel
    Then the detail panel appears immediately without a slide or fade animation
    And the detail panel content is fully visible and accessible on the next render frame
