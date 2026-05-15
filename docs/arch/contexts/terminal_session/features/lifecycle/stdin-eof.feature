# DDD role: BehaviouralSpecification
# Bounded context: terminal_session
# References: ADR-0017

Feature: Stdin EOF — Ctrl-D sends EOF marker and process terminates cleanly
  As an operator
  I want pressing Ctrl-D to terminate the remote shell process cleanly
  So that the session closes without leaving orphaned processes in the container

  Background:
    Given a TerminalSessionActor for "web-0" is in "open" state
    And a shell process /bin/sh is running in the container

  @happy @lifecycle
  Scenario: Ctrl-D sends EOF on stdin channel and shell exits
    When the operator presses Ctrl-D in the terminal UI
    Then the TerminalSessionActor sends a zero-length payload frame on channel 0x00 (stdin EOF)
    And the remote shell process receives EOF on its stdin
    And the shell exits cleanly
    And the server sends the exit code via channel 0x03 (v5 error channel): {"ExitCode":0}
    And the UI displays "Process exited (0)" in a non-error colour
    And the session transitions from "open" to "closing" and then "closed"

  @failure @lifecycle
  Scenario: Process exits with non-zero code — UI shows warning
    When the remote command exits with code 1
    Then the exit code is delivered on channel 0x03 as {"ExitCode":1}
    And the UI displays "Process exited (1)" in a warning colour
    And the session transitions to "closed"

  @happy @lifecycle
  Scenario: Operator closes the tab without Ctrl-D — cooperative cancel within 200 ms
    When the operator closes the terminal tab
    Then Task.cancel is sent to the TerminalSessionActor
    And the actor calls URLSessionWebSocketTask.cancel(with:reason:) within 200 milliseconds
    And the underlying HTTP connection is released
    And the session transitions to "closed"
    And no zombie processes remain attached to the exec WebSocket on the server

  @failure @lifecycle
  Scenario: Idle timeout after 30 minutes closes the session automatically
    Given the terminal session has received no stdin or stdout activity for 30 minutes
    When the idle-check cooperative task fires
    Then the TerminalSessionActor closes the session via Task.cancel
    And the UI displays "Session closed due to inactivity"
    And the session transitions to "closed"
