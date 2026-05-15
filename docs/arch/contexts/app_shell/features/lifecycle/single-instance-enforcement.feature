# DDD role: BehaviouralSpecification
# Bounded context: app_shell
# References: ADR-0021, ADR-0026

Feature: Single-instance enforcement via Lease file
  As an operator
  I want only one instance of K8sManager to run at a time on a machine
  So that multiple instances do not create conflicting cluster sessions and duplicated watchers

  Background:
    Given the application is already running with PID 12345
    And a Lease file at "~/.config/k8smanager/instance.lock" contains PID 12345

  @happy @lifecycle
  Scenario: Second launch detects existing PID via Lease file and exits with friendly error
    When a second instance of K8sManager is launched
    Then the second instance reads "~/.config/k8smanager/instance.lock"
    And finds PID 12345 which corresponds to a running process
    And the second instance exits immediately without starting any cluster sessions
    And a dialog or log message displays "K8sManager is already running (PID 12345). Use the existing instance."

  @failure @lifecycle
  Scenario: Lease file contains a stale PID from a crashed previous run
    Given the previous instance crashed without cleaning up the Lease file
    And the Lease file contains PID 99999 which is no longer running
    When a new instance launches
    Then the new instance reads "~/.config/k8smanager/instance.lock"
    And verifies that PID 99999 is not a running process (using kill(pid, 0))
    And treats the Lease file as stale and overwrites it with the new PID
    And the new instance starts normally

  @happy @lifecycle
  Scenario: Lease file is cleaned up on graceful quit
    Given the application is running and holds the Lease file with its PID
    When the operator quits K8sManager gracefully
    Then the Lease file is deleted before the process exits
    And the next launch finds no Lease file and starts without the stale-PID check

  @failure @lifecycle
  Scenario: Lease file write permission denied — application warns and continues without enforcement
    Given the directory "~/.config/k8smanager/" has its write permission revoked (chmod 555)
    When the application launches
    Then the Lease file write fails with a permission error
    And the application logs a warning "Cannot write instance lock file — single-instance enforcement disabled"
    And the application continues launching (enforcement is best-effort, not a hard gate)
