# DDD role: ChaosScenario
# Bounded context: terminal_session
# Failure mode: F15 (pod killed during exec session)
# References: ADR-0041, ADR-0026, ADR-0028

Feature: Pod killed during active exec session surfaces exit code and marks session Closed
  As a cluster operator
  I need the terminal to surface the exit condition and close cleanly when the exec pod is killed
  So that I understand why the session ended and can take remedial action

  Background:
    Given an exec session "exec-1" is active in pod "busybox-runner" container "main"
    And the SPDY/v5 channel is open on the "exec" sub-resource
    And the terminal is displaying a live shell prompt

  @chaos @network
  Scenario: Pod deletion causes v5 channel close and exit code is surfaced in the terminal
    When the pod "busybox-runner" is deleted while the exec session is active
    Then the v5 channel receives a stream-close frame or EOF
    And the terminal displays the message "Session closed — exit code: 137 (SIGKILL)"
    And the session "exec-1" transitions to state "Closed" with reason "pod-deleted"
    And the UI marks the terminal tab with a "Closed" badge

  @chaos @network
  Scenario: Process exits normally inside the container and exit code 0 is surfaced
    Given the exec session "exec-1" is running the command "exit 0" inside the container
    When the process exits with code 0
    Then the v5 channel closes cleanly
    And the terminal displays "Session closed — exit code: 0"
    And the session transitions to "Closed" with reason "process-exited"

  @chaos @network
  Scenario: OOMKill of the container during exec surfaces exit code 137 and oom reason
    When the container "main" in pod "busybox-runner" is OOMKilled by the kernel
    Then the exec channel receives an error or EOF
    And the terminal displays "Session closed — exit code: 137 (OOMKilled)"
    And the session transitions to "Closed" with reason "oom-kill"
    And the event "ExecSessionClosed" is emitted with fields "exitCode=137" and "cause=oom"
