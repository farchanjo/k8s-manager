# DDD role: BehaviouralSpecification
# Bounded context: app_shell
# References: ADR-0021, ADR-0026, ADR-0033

Feature: Cold launch state restoration for cluster sessions, chat sessions, and terminal
  As an operator
  I want K8sManager to restore my working context on every launch
  So that I can resume exactly where I left off without manually reopening surfaces

  Background:
    Given the previous session quit cleanly with the following open surfaces:
      | Type            | Count | Detail                            |
      | cluster sessions | 3    | prod-us-east-1, staging-eu, dev  |
      | chat sessions   | 2    | "debug prod" and "architecture Q" |
      | terminal        | 1    | exec session on "worker-0"        |
    And all view_state.json files exist under their respective cluster directories

  @happy @lifecycle
  Scenario: Cold launch restores all 3 cluster sessions and 2 chat sessions in parallel
    When the application launches
    Then a parallel TaskGroup spawns ClusterSessionActors for all 3 clusters
    And each actor loads its view_state.json and emits a "connected" event
    And both chat sessions are loaded from "storage.sqlite3" and shown in the chat sidebar
    And the active context is restored to "prod-us-east-1" (last active cluster)

  @happy @lifecycle
  Scenario: Terminal session reopen prompt is shown and accepted
    Given 1 terminal session was open at quit
    When the application completes the cluster reconnection phase
    Then a prompt appears: "Reopen 1 terminal from last session?"
    When the operator accepts the prompt
    Then a new exec session is opened for "worker-0" in the appropriate cluster
    And the new session transitions to "open" state
    And the terminal tab is visible in the UI

  @failure @lifecycle
  Scenario: Terminal session prompt dismissed — terminal not reopened
    Given the terminal reopen prompt is shown
    When the operator presses "Dismiss"
    Then no exec session is opened
    And the terminal tab is not shown in the UI
    And the prompt is not shown again in this session

  @failure @lifecycle
  Scenario: One of three cluster sessions fails to reconnect on launch
    Given "dev" cluster has a misconfigured kubeconfig (the API server is offline)
    When the application launches and spawns ClusterSessionActors in parallel
    Then the actors for "prod-us-east-1" and "staging-eu" connect successfully
    And the actor for "dev" transitions to "degraded" with reason "api-server-unreachable"
    And a non-dismissible banner appears for "dev" cluster with a retry affordance
    And the other two sessions are fully functional

  @happy @lifecycle
  Scenario: First launch with no previous state creates fresh environment
    Given no "storage.sqlite3" exists at "~/.config/k8smanager/"
    When the application launches for the first time
    Then "~/.config/k8smanager/" is created with permissions 0700
    And "storage.sqlite3" is initialised with WAL mode
    And the onboarding flow is presented (no cluster sessions, no chat sessions)
