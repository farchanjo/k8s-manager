# DDD role: ChaosScenario
# Bounded context: terminal_session
# Failure mode: resize-event flood (protocol amplification)
# References: ADR-0041, ADR-0028, ADR-0029

Feature: Terminal resize-event flood is collapsed by debouncer to safe rate
  As a cluster operator
  I need rapid window-resize events to be debounced before sending control frames
  So that the exec SPDY channel is not flooded with superfluous resize messages

  Background:
    Given an exec session "exec-2" is active in pod "tools-runner"
    And the terminal emulator is visible and accepting resize events
    And the debouncer is configured with a 100ms collapse window and a 10 frames/sec cap

  @chaos @concurrency
  Scenario: 100 resize events per second are collapsed to at most 10 control frames per second
    When the window-resize event fires 100 times within 1 second (simulated by resize-flood fixture)
    Then the debouncer emits at most 10 SPDY "resize" control frames to the exec channel in that 1-second window
    And the terminal remains responsive (no UI freeze or lag)
    And the exec session "exec-2" stays in state "Active" throughout

  @chaos @concurrency
  Scenario: Each collapsed resize frame carries the final dimensions from the burst
    Given 50 resize events arrive within 100 milliseconds with varying dimensions
    And the last resize event has dimensions 220 columns x 50 rows
    When the debouncer emits the single collapsed frame for that burst
    Then the emitted SPDY resize control frame specifies "width=220 height=50"
    And no intermediate dimensions from the burst are forwarded

  @chaos @concurrency
  Scenario: Resize events after a quiet period are sent without delay
    Given 500ms have elapsed since the last resize event
    When a single resize event fires with dimensions 180 columns x 45 rows
    Then the debouncer emits the resize control frame within 50ms (no accumulated delay)
    And only 1 control frame is sent for that single event
