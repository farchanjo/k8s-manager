# DDD role: BehaviouralSpecification
# Bounded context: resource_browser
# References: ADR-0010, ADR-0012, ADR-0026, ADR-0030
# CUE schema: contexts/resource_browser/schemas/draft.cue

Feature: Secret manifest redaction before draft persistence
  As a security-conscious operator
  I want secret values to be automatically redacted in any persisted draft
  So that plaintext or base64-encoded credentials never land in the SQLite database

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And the resource browser is showing the "default" namespace
    And the "editor_drafts" table exists in "storage.sqlite3"

  @security @happy
  Scenario: Opening a Secret manifest triggers redaction before auto-save
    Given a Secret named "db-creds" exists with "data.DB_PASS: c2VjcmV0" and "data.DB_USER: YWRtaW4="
    When the operator opens "db-creds" in the integrated editor
    And the auto-save debounce elapses (within 5 seconds)
    Then the DraftAutoSaver writes a row to "editor_drafts"
    And the row field "sensitiveContentRedacted" equals true
    And the stored draft content under "data:" replaces all values with "[REDACTED]"
    And the stored draft content under "stringData:" replaces all values with "[REDACTED]"
    And the string "c2VjcmV0" does NOT appear anywhere in "storage.sqlite3"

  @security @happy
  Scenario: stringData values are also redacted for Secrets
    Given a Secret named "tls-creds" contains "stringData.tls.crt: <pem-content>" and "stringData.tls.key: <pem-key>"
    When the operator edits the Secret and the auto-save fires
    Then both "tls.crt" and "tls.key" values in "stringData:" are replaced with "[REDACTED]"
    And the draft row has "sensitiveContentRedacted" equal to true
    And the raw PEM content is NOT stored in the draft row

  @happy @lifecycle
  Scenario: Non-secret resource draft is saved without redaction flag
    Given a ConfigMap named "app-config" is open in the editor
    When the operator edits "data.env" and the auto-save fires
    Then the draft row has "sensitiveContentRedacted" equal to false
    And the full buffer content including "data.env" values is stored verbatim
    And the raw values ARE present in the draft row (no sensitive data to redact)

  @failure @lifecycle
  Scenario: Draft restore for a redacted Secret shows a warning before restoring
    Given an older session left a redacted draft for "db-creds" in "editor_drafts"
    When the operator navigates to "db-creds" and the recovery banner appears
    And the operator clicks "Restore"
    Then the editor buffer is populated with the redacted content (values show "[REDACTED]")
    And a non-dismissible warning banner states "Secret values were redacted in this draft — re-enter sensitive fields before applying"
    And the Apply button remains disabled until the operator replaces all "[REDACTED]" placeholders
