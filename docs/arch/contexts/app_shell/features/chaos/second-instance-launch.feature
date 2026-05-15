# DDD role: ChaosScenario
# Bounded context: app_shell
# Failure mode: duplicate process launch (single-instance guard)
# References: ADR-0041, ADR-0022, ADR-0029

Feature: Second app instance detects running instance and forwards arguments before exiting
  As a cluster operator
  I need only one app instance to run per user session
  So that state is never split across two processes and the UI remains consistent

  Background:
    Given a first instance of K8sManager is running with a valid process lock
    And the first instance is connected to clusters "prod-eu" and "staging-us"

  @chaos @concurrency
  Scenario: Second instance launch detects the running instance via process lock
    When the operator double-clicks the app icon (or opens from CLI) while the first instance is running
    Then the second instance detects the existing process lock within 1 second of launch
    And the second instance does NOT initialize a new UI window or database connection
    And the second instance forwards any command-line arguments to the first instance via IPC
    And the second instance exits with code 0

  @chaos @concurrency
  Scenario: First instance receives forwarded arguments and acts on them
    Given the second instance forwards the argument "--open-cluster prod-eu"
    When the first instance receives the IPC message
    Then the first instance brings its window to the foreground
    And the first instance acts on "--open-cluster prod-eu" (e.g., focuses the prod-eu session)
    And no new window or process is created

  @chaos @concurrency
  Scenario: Stale lock from a previous crash is cleared and a new instance starts normally
    Given a stale process lock file exists from a prior app crash (PID no longer running)
    When a new instance launches
    Then the new instance detects the lock PID is not running
    And the new instance clears the stale lock
    And the new instance starts normally and creates a fresh lock
    And the metric "stale_lock_cleared_total" increments by 1
