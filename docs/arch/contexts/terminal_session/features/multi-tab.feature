Feature: Multi-tab terminal sessions
  As a cluster operator using K8sManager
  I want to manage multiple independent terminal sessions simultaneously in tabs
  So that I can work across several Pods or Nodes without losing context

  Background:
    Given a kubeconfig context "prod-cluster" is active
    And the cluster is reachable and responds to API requests

  Scenario: Open N parallel sessions where each runs in its own TerminalSessionActor
    Given no terminal sessions are currently open
    When the operator opens a terminal for Pod "api-pod-001" container "api"
    And the operator opens a terminal for Pod "db-pod-001" container "postgres"
    And the operator opens a terminal for Pod "cache-pod-001" container "redis"
    Then three TerminalSession aggregates exist with distinct UUIDv7 ids
    And each session has status "open"
    And each session is owned by a distinct TerminalSessionActor instance
    And each actor holds an independent URLSessionWebSocketTask
    And output received on one session does not appear in any other session
    And all three tabs are visible in the terminal tab bar

  Scenario: Reorder tabs without affecting session state
    Given three open terminal sessions for "api-pod-001", "db-pod-001", "cache-pod-001"
    And the tabs are displayed in creation order
    When the operator drags the "db-pod-001" tab to the first position
    Then the tab bar shows "db-pod-001", "api-pod-001", "cache-pod-001"
    And all three sessions remain in "open" status
    And the WebSocket connections are unaffected by the reorder
    And the OpenTerminalsReadModel reflects the new display order
    And stdin typed into any tab is still forwarded to the correct session

  Scenario: Close one tab without affecting other sessions
    Given three open terminal sessions for "api-pod-001", "db-pod-001", "cache-pod-001"
    When the operator closes the tab for "db-pod-001"
    Then the TerminalSessionActor for "db-pod-001" receives cooperative cancel
    And the WebSocket connection for "db-pod-001" closes within 200 milliseconds
    And the session for "db-pod-001" transitions to "closed"
    And the tab for "db-pod-001" is removed from the tab bar
    And the sessions for "api-pod-001" and "cache-pod-001" remain in "open" status
    And their WebSocket connections are unaffected
    And the terminal output in the remaining tabs is preserved

  Scenario: Idle timeout closes session after 30 minutes of inactivity and shows message
    Given an open terminal session for Pod "idle-pod-001" container "shell"
    And the session has been open for 30 minutes with no stdin or stdout activity
    When the idle-timeout check fires in the TerminalSessionActor
    Then the session status transitions to "closing" then "closed"
    And the WebSocket connection is closed by the actor
    And the terminal UI for "idle-pod-001" displays the message
      "Session closed due to inactivity (30 min)"
    And the tab remains visible but indicates the session is closed
    And the operator can open a new session from the same tab or by reopening
    And no automatic reconnect is attempted

  Scenario: Simultaneous stdin input to two sessions delivers bytes to correct sessions only
    Given two open terminal sessions:
      - Session A for Pod "app-pod-01" container "app"
      - Session B for Pod "app-pod-02" container "app"
    And Session A is the active (focused) tab
    When the operator types "hello" in the active tab
    Then five StdinFrames are sent on channel 0 of Session A's WebSocket connection
    And zero StdinFrames are sent on Session B's WebSocket connection
    And Session B's terminal output is unaffected
