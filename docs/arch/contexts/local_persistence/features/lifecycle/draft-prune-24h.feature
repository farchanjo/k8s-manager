# DDD role: BehaviouralSpecification
# Bounded context: local_persistence
# References: ADR-0010, ADR-0026, ADR-0030
# CUE schema: contexts/resource_browser/schemas/draft.cue

Feature: Auto-saved draft pruning after 24 hours with no active session
  As an operator
  I want stale auto-saved drafts to be pruned on launch
  So that the "editor_drafts" table does not accumulate old drafts for resources I am no longer editing

  Background:
    Given the "editor_drafts" table contains several auto-saved drafts of varying ages

  @happy @lifecycle
  Scenario: Drafts older than 24 hours with no active editor session are pruned on launch
    Given the table contains:
      | Draft      | Age    | Active Session? | sensitiveContentRedacted |
      | draft-A    | 25h    | No              | false                    |
      | draft-B    | 23h    | No              | false                    |
      | draft-C    | 48h    | No              | true                     |
      | draft-D    | 12h    | Yes             | false                    |
    When the application launches and the draft pruning routine runs
    Then draft-A and draft-C are deleted from "editor_drafts" (age > 24h, no active session)
    And draft-B is retained (age < 24h)
    And draft-D is retained (active session exists regardless of age)
    And the deletion is wrapped in a single SQLite transaction

  @failure @lifecycle
  Scenario: Pruning does not delete manually saved (non-auto-saved) drafts
    Given the table contains a draft with "autoSaved=false" created 48 hours ago
    When the pruning routine runs
    Then the non-auto-saved draft is NOT deleted (operator explicitly chose to save it)
    And only rows with "autoSaved=true" older than 24 hours are candidates for deletion

  @security @lifecycle
  Scenario: Redacted drafts are pruned by the same age-based rule
    Given a draft with "sensitiveContentRedacted=true" and age 26 hours exists
    When the pruning routine runs
    Then the redacted draft is deleted by the standard 24-hour auto-save prune rule
    And no special handling is required for redacted drafts (the redaction happened at write time)

  @happy @lifecycle
  Scenario: Pruning completes before the first user-facing interaction
    When the application launches
    Then the draft pruning routine runs after migrations are applied but before the UI is shown
    And the pruning duration is under 100 milliseconds (indexed query on autoSaved and createdAt)
    And the pruning does not block the main actor thread
