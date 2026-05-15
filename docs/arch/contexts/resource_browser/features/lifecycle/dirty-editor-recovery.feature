# DDD role: BehaviouralSpecification
# Bounded context: resource_browser
# References: ADR-0012, ADR-0026, ADR-0030, ADR-0034

Feature: Dirty editor draft recovery after app crash
  As an operator
  I want unsaved YAML edits to be recoverable after a crash
  So that I do not lose work on large or complex manifests

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And the integrated editor (ADR-0030) is open with a Deployment "api-server" in editing mode
    And the operator has made changes that set isDirty to true
    And the editor state is "dryRunComplete"

  @happy @lifecycle
  Scenario: Draft is saved atomically within 5 seconds of a dirty change
    When the operator modifies "spec.replicas" from 3 to 5 and the debounce window elapses
    Then within 5 seconds a #Draft row is written to the "editor_drafts" table in "storage.sqlite3"
    And the draft row has "autoSaved" equal to true
    And the draft row has "sourceFormat" equal to "yaml"
    And the draft row has "sensitiveContentRedacted" equal to false (Deployment has no secret data)
    And the draft content equals the buffer state at the time of the auto-save

  @happy @lifecycle
  Scenario: Relaunch after crash presents draft recovery banner for dirty editor
    Given the app crashed while "api-server" editor was dirty with an unsaved draft in "editor_drafts"
    When the application relaunches and the operator navigates to "api-server" in the resource browser
    Then the editor shows a dismissible banner "Unsaved draft from <timestamp> — Restore / Discard"
    And clicking Restore loads the draft content into the editor buffer
    And the editor state transitions to "editing"
    And isDirty is true after restore

  @security @lifecycle
  Scenario: Draft for a Secret resource is saved with sensitive content redacted
    Given the editor is open with a Secret named "db-creds" in editing mode
    And the buffer contains "data:\n  DB_PASS: c2VjcmV0\n  DB_USER: YWRtaW4="
    When the auto-save debounce elapses
    Then the #Draft row written to "editor_drafts" has "sensitiveContentRedacted" equal to true
    And the stored draft content replaces all values under "data:" and "stringData:" with "[REDACTED]"
    And the raw secret values are NOT present in the SQLite file at any point

  @failure @lifecycle
  Scenario: Draft older than 24 hours is pruned on next launch
    Given the "editor_drafts" table contains a draft for "api-server" created 25 hours ago
    And no active editor session is associated with that draft
    When the application launches
    Then the draft pruning routine deletes rows with "autoSaved=true" older than 24 hours
    And the draft for "api-server" is removed from "editor_drafts"
    And no recovery banner is shown for "api-server" on the next open
