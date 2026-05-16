# DDD role: BehaviouralSpecification
# DDD Role: ApplicationService (docked terminal orchestration), Aggregate (DockedTerminalPane)
# Context: app_shell
# Related ADRs: ADR-0057 (Bottom-docked terminal pane), ADR-0017 (Terminal sessions), ADR-0051 (Multi-cluster workspace)
Feature: Bottom-docked terminal pane

  Background:
    Given the application is running with at least one pinned cluster in connected state
    And the operator has completed onboarding
    And no docked terminal tabs are open

  Scenario: Open node debug shell from the node detail drawer header
    Given the operator has selected a Node resource named "worker-01" in the Nodes list
    And the resource detail drawer is open showing the Node header for "worker-01"
    When the operator activates the "Shell to Node: worker-01" button in the drawer header action bar
    Then the ADR-0012 confirmation sheet is presented with the text "This will create an ephemeral debug pod on node worker-01"
    When the operator confirms by pressing "Continue"
    Then the docked terminal pane slides up from the bottom of the content area
    And a new docked tab labelled "Node: worker-01" is visible in the pane tab bar
    And the tab connection state indicator shows the connecting state
    And the PTY viewport for the active tab shows the banner "Connecting ..."
    And the resource detail drawer for "worker-01" remains visible above the pane
    And the Nodes list remains visible above the detail drawer
    When the node debug session reaches open state
    Then the connection state banner is removed
    And the live PTY viewport is presented in the active tab

  Scenario: Resize the docked pane by dragging the top-edge handle
    Given one docked terminal tab is open and the pane is visible
    And the pane height is at the default 33 percent of the content area height
    When the operator drags the top-edge resize handle upward by 80 points
    Then the pane height increases by 80 points
    And the resource list area above the pane shrinks by the same amount
    And the pane height remains above the minimum of 120 points
    When the operator double-clicks the top-edge resize handle
    Then the pane height resets to the default 33 percent of the content area height with a spring animation

  Scenario: Multiple docked tabs coexist for pod-exec and node-debug sessions
    Given the operator has opened a pod-exec session to pod "api-server-abc12" in namespace "kube-system"
    And a docked tab labelled "Pod: api-server-abc12" is open and in connected state
    When the operator navigates to the Nodes list and opens a node debug shell for node "worker-02"
    And confirms the ADR-0012 mutation sheet
    Then a second docked tab labelled "Node: worker-02" appears in the pane tab bar
    And the pane tab bar shows two tabs in open order
    And switching to the "Pod: api-server-abc12" tab shows that tab's PTY viewport
    And the "Node: worker-02" session continues running in the background
    And closing the "Pod: api-server-abc12" tab removes it from the tab bar
    And the "Node: worker-02" tab remains open and connected

  Scenario: Fullscreen toggle expands and collapses the docked pane
    Given one docked terminal tab is open with the pane at default height
    When the operator activates the fullscreen toggle button in the pane tab bar
    Then the pane expands to fill the full content area height excluding the status bar
    And the resource list and detail drawer are no longer visible
    And the fullscreen toggle button changes to the collapse affordance
    When the operator activates the fullscreen toggle button again
    Then the pane collapses back to the height it had before fullscreen was activated
    And the resource list and detail drawer are visible again

  Scenario: Pane height and open tabs persist across application launches
    Given one docked terminal tab labelled "Node: worker-01" is open with kind node-debug
    And the operator has resized the pane to 240 points
    When the operator quits the application
    And relaunches the application
    Then the docked pane is visible at 240 points height
    And one docked tab labelled "Node: worker-01" is present in the tab bar
    And the tab connection state indicator shows the closed state
    And the PTY viewport for that tab shows the banner "Session closed" with a "Reopen" button
    And no TerminalSessionActor has been started automatically
