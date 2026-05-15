# DDD role: ChaosScenario
# Bounded context: resource_browser
# Failure mode: concurrency (draft prune races active edit session)
# References: ADR-0041, ADR-0030, ADR-0033

Feature: Draft prune job does not delete an actively-edited draft approaching age limit
  As a cluster operator
  I need the prune scheduler to respect active edit sessions
  So that I do not lose unsaved work when a draft crosses the 24-hour age boundary

  Background:
    Given a draft "draft-nginx-v2" was created 23 hours and 59 minutes ago
    And the editor for "draft-nginx-v2" is currently open with unsaved changes
    And the draft prune scheduler runs on a 60-second interval

  @chaos @concurrency
  Scenario: Prune scheduler skips a draft that has an active editor session
    When the prune scheduler evaluates drafts older than 24 hours
    Then "draft-nginx-v2" is NOT pruned despite being within 1 minute of the age threshold
    And the prune scheduler records "skipped draft-nginx-v2: active editor session"
    And the editor remains open with all unsaved changes intact

  @chaos @concurrency
  Scenario: Draft is pruned only after the editor session closes without a save
    Given the editor session for "draft-nginx-v2" is closed without saving
    And the draft age is now 24 hours and 5 minutes
    When the prune scheduler runs
    Then "draft-nginx-v2" is pruned
    And the metric "draft_pruned_orphan_total" increments by 1

  @chaos @concurrency
  Scenario: Saving a draft resets its age timestamp and prevents pruning
    Given the editor for "draft-nginx-v2" is open with 23h59m age
    When the operator saves the draft (creating a new version)
    Then the draft's "updated_at" timestamp is refreshed to now
    And the next prune cycle does not prune the draft
