# DDD role: BehaviouralSpecification
# Bounded context: terminal_session
# References: ADR-0017

Feature: Terminal window resize — channel 4 frame with debouncing
  As an operator
  I want terminal resize events to be sent efficiently to the remote container
  So that the container's tty dimensions stay in sync with my window without flooding the WebSocket

  Background:
    Given a TerminalSessionActor for "web-0" is in "open" state
    And the current terminal dimensions are 80 columns × 24 rows

  @happy @lifecycle
  Scenario: Window resize sends a channel-4 frame with JSON dimensions
    When the operator resizes the terminal window to 120 columns × 40 rows
    And 100 milliseconds elapse (debounce window)
    Then exactly one WebSocket binary frame is sent
    And the frame first byte is 0x04 (channel 4 — resize)
    And the remaining bytes are the UTF-8 encoding of {"Width":120,"Height":40}
    And the TerminalSessionActor's current dimensions are updated to 120 × 40

  @happy @lifecycle
  Scenario: Rapid resize events are debounced to one frame per 100 milliseconds
    When the operator drags the resize handle generating 50 resize events in 80 milliseconds
    And 100 milliseconds elapse after the last event
    Then exactly one resize frame is sent (the final size)
    And intermediate resize events are discarded
    And the sent frame carries the dimensions of the final resize event only

  @failure @lifecycle
  Scenario: Resize during v4 fallback session still works (no error channel)
    Given the cluster negotiated "v4.channel.k8s.io" (downgraded from v5)
    When the operator resizes the terminal to 100 × 30
    Then a resize frame is sent on channel 4 with {"Width":100,"Height":30}
    And the TerminalSessionActor handles the v4 channel set without crashing
    And stderr information is delivered via the v4 stderr stream (channel 2)

  @failure @lifecycle
  Scenario: Resize frame send failure does not crash the session
    Given the WebSocket connection is momentarily unable to send
    When a resize frame write throws an error
    Then the TerminalSessionActor catches the error without propagating it to the actor boundary
    And the session remains in "open" state
    And the next resize event after recovery is sent normally
