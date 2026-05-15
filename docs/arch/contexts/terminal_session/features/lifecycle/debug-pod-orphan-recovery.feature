# DDD role: BehaviouralSpecification
# Bounded context: terminal_session
# References: ADR-0011, ADR-0012, ADR-0017

Feature: Debug pod orphan detection and recovery on relaunch
  As an operator
  I want orphaned debug pods from previous crashed sessions to be detected and presented for cleanup
  So that stale privileged pods do not accumulate on nodes

  Background:
    Given the application crashed during a previous session while a debug pod "node-debugger-node-1-abc123" was open
    And the debug pod is still running in the "default" namespace
    And the pod was created 90 seconds before the current launch (exceeding the 60-second grace)

  @happy @lifecycle
  Scenario: Orphan debug pod older than 60s grace is detected on launch
    When the application launches and scans for debug pods with the label "app.kubernetes.io/managed-by=K8sManager"
    Then the scan finds "node-debugger-node-1-abc123" with creationTimestamp 90 seconds ago
    And the pod age exceeds the 60-second grace period
    And the application prompts the operator: "Orphaned debug pod found: node-debugger-node-1-abc123 — Delete?"
    And the prompt includes the pod name, node, and age

  @happy @lifecycle
  Scenario: Operator confirms deletion of the orphan pod
    Given the orphan detection prompt is shown for "node-debugger-node-1-abc123"
    When the operator confirms deletion
    Then a DELETE request is dispatched to the Kubernetes API for the pod
    And an audit entry is written with verb "delete" and outcome "succeeded"
    And the pod is removed from the cluster
    And no active TerminalSessionActor is affected by this cleanup

  @happy @lifecycle
  Scenario: Operator dismisses the orphan prompt — pod remains and prompt is not shown again this session
    Given the orphan detection prompt is shown
    When the operator presses "Dismiss"
    Then no DELETE request is dispatched
    And the orphan pod remains in the cluster
    And the prompt is not shown again during the current application session

  @failure @lifecycle
  Scenario: Debug pod within the 60-second grace period is not presented for deletion
    Given the previous session crashed 30 seconds ago and the debug pod age is 30 seconds
    When the application launches and scans for debug pods
    Then the pod "node-debugger-node-1-abc123" is found but its age is below 60 seconds
    And the orphan deletion prompt is NOT shown
    And the pod is left running in case the session is expected to be resumed soon

  @security @lifecycle
  Scenario: Privileged debug pod creation requires double-confirm via ADR-0012 flow
    Given the operator initiates a node debug session for "node-1"
    When the application constructs the debug pod with hostNetwork=true, hostPID=true, privileged=true
    Then the ADR-0012 double-confirm modal is presented before the Pod creation API call
    And the operator must confirm once (single-confirm is required per ADR-0012 for node-debug Pod creation)
    And an audit entry is written with verb "create" referencing the NodeDebugDescriptor
