# DDD role: BehaviouralSpecification
# Bounded context: terminal_session
# References: ADR-0017

Feature: Exit code delivery — v5 channel 3 vs v4 stderr close
  As an operator
  I want exit codes to be surfaced consistently in the UI regardless of subprotocol version
  So that I always know whether the remote command succeeded or failed

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state

  @happy @lifecycle
  Scenario: v5 session delivers exit code on channel 3
    Given the exec session negotiated "v5.channel.k8s.io"
    And the session is in "open" state
    When the remote process exits with code 42
    Then the server sends a frame on channel 0x03 with payload {"ExitCode":42}
    And the TerminalSessionActor captures exitCode 42 from the channel-3 frame
    And the UI displays "Process exited (42)" in a warning colour
    And the session transitions to "closed" with the captured exitCode 42

  @happy @lifecycle
  Scenario: v4 session derives exit code from stderr stream close heuristic
    Given the exec session negotiated "v4.channel.k8s.io" (server downgrade from v5)
    And the session is in "open" state
    When the remote process exits and the server closes the stderr stream (channel 2)
    Then the TerminalSessionActor uses the v4 fallback: infer exit from stderr-close with no prior error payload
    And the UI displays "Process exited" (exit code not available in v4 without a prior error frame)
    And the session transitions to "closed"

  @happy @lifecycle
  Scenario: Exit code 0 shown in non-error colour; non-zero codes shown in warning colour
    Given an exec session in "open" state
    When the remote process exits with code 0
    Then the UI displays "Process exited (0)" in the primary (non-warning) text colour
    When a separate session's remote process exits with code 127
    Then that session's UI displays "Process exited (127)" in the warning text colour

  @failure @lifecycle
  Scenario: WebSocket closes without an exit-code channel message
    Given a v5 exec session is in "open" state
    When the WebSocket closes unexpectedly with no channel-3 message (e.g., Pod evicted)
    Then the TerminalSessionActor sets exitCode to nil
    And the session transitions to "error" state
    And the UI displays "Session terminated unexpectedly — no exit code received"
