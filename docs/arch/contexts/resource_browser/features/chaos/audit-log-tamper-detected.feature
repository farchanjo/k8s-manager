# DDD role: ChaosScenario
# Bounded context: resource_browser
# Failure mode: F17 (audit log integrity violation)
# References: ADR-0041, ADR-0024, ADR-0030

Feature: Corrupted audit entry digest halts new audit writes
  As a cluster operator
  I need the audit subsystem to detect tampered entries and freeze writes
  So that audit trail integrity is preserved and no further entries corrupt the chain

  Background:
    Given the cluster_mutation_audit store contains 50 valid entries
    And each entry carries a valid HMAC "previous_entry_digest" linking the chain

  @chaos @io
  Scenario: Injected digest corruption triggers integrity failure and red banner
    Given a test fixture corrupts entry #48's "previous_entry_digest" field directly in SQLite
    When the audit verification pass runs (triggered on next mutation or on app resume)
    Then the verification pass detects the broken chain at entry #48
    And the UI displays a red persistent banner "Audit integrity check failed — chain broken at entry #48"
    And the banner is not dismissible without an explicit operator action

  @chaos @io
  Scenario: No new audit entries are accepted while the chain is broken
    Given the audit integrity check has failed at entry #48
    When the operator applies a manifest (which would normally produce an audit entry)
    Then the mutation is rejected with "Audit log integrity compromised — writes suspended"
    And the mutation is not forwarded to the API server
    And the metric "audit_writes_suspended_total" increments by 1

  @chaos @io
  Scenario: Operator exports and resets the audit log to resume writes
    Given the audit chain is broken and writes are suspended
    When the operator clicks "Export audit log" and then "Reset audit chain"
    Then the full audit log (including the corrupted entry) is exported to a local file
    And the audit store is cleared and a new genesis entry is written
    And new audit entries are accepted after the reset
    And the red banner is cleared

  @chaos @io
  Scenario: Other release operations are unaffected while audit writes are suspended
    Given audit writes are suspended due to an integrity failure
    When the operator navigates to a different namespace and performs a LIST
    Then the LIST succeeds without any error
    And read-only operations are not blocked by the audit suspension
