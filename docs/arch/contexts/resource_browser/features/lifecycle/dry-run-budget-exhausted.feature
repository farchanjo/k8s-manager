# DDD role: BehaviouralSpecification
# Bounded context: resource_browser
# References: ADR-0012, ADR-0030, ADR-0035

Feature: Dry-run circuit breaker when typing rapidly
  As an operator
  I want the dry-run budget circuit breaker to engage when I type faster than the debounce can handle
  So that the API server is not flooded with dry-run requests during rapid edits

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Deployment "api-server" is open in the editor in "editing" state
    And the dry-run debounce is set to 500 milliseconds

  @happy @lifecycle
  Scenario: Rapid typing within debounce window produces only one dry-run request
    When the operator types 50 characters in rapid succession over 300 milliseconds
    And 500 milliseconds elapse after the last keystroke
    Then exactly one PATCH request with dryRun=All is sent to the API server
    And the editor state transitions through "dryRunning" to "dryRunComplete"
    And the diff preview is populated with the result

  @failure @lifecycle
  Scenario: Dry-run circuit breaker engages after sustained continuous typing
    Given the editor has already dispatched 10 dry-run requests in the last 60 seconds
    And the circuit breaker threshold is configured at 10 requests per 60 seconds
    When the operator continues typing and another debounce window elapses
    Then no new PATCH with dryRun=All is sent to the API server
    And the editor displays a "dry-run paused" indicator in the toolbar
    And the editorState remains "editing" (not "dryRunning")
    And after 60 seconds the circuit breaker resets and dry-run resumes

  @failure @lifecycle
  Scenario: Dry-run API server error does not crash the editor session
    Given the dry-run debounce has elapsed and a PATCH with dryRun=All is dispatched
    When the API server returns HTTP 422 Unprocessable Entity with a field validation error
    Then the editorState transitions to "dryRunComplete" with a non-empty "validationErrors" list
    And the validation error is shown as a diagnostic in the gutter
    And the Apply button remains disabled while validation errors exist
    And no audit entry is written (dry-run is not a mutation per ADR-0012)

  @lifecycle @idempotency
  Scenario: Undoing all changes clears the dry-run result and resets editor to clean
    Given the editor has a pending dry-run result with a non-empty diffPreview
    When the operator presses Cmd+Z until isDirty is false
    Then the diffPreview is cleared
    And the editorState transitions to "idle"
    And no pending dry-run request is in flight
    And the Apply button is disabled (nothing to apply)
