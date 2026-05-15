# DDD role: BehaviouralSpecification
# Bounded context: local_persistence
# References: ADR-0010, ADR-0012

Feature: SQLite trigger prevents mutation of the cluster_mutation_audit table
  As an operator and auditor
  I want the audit table to be append-only enforced at the database layer
  So that no application code or operator action can alter or delete historical audit entries

  Background:
    Given "storage.sqlite3" contains a "cluster_mutation_audit" table
    And the table has a SQLite trigger "audit_anti_update" that fires on UPDATE
    And the table has a SQLite trigger "audit_anti_delete" that fires on DELETE

  @security @happy
  Scenario: Attempt to UPDATE an audit row triggers RAISE and fails
    Given an audit entry with id "entry-001" and outcome "succeeded" exists
    When code attempts "UPDATE cluster_mutation_audit SET outcome='failed' WHERE id='entry-001'"
    Then the SQLite trigger raises an ABORT with message "cluster_mutation_audit is append-only"
    And the UPDATE is rolled back by SQLite
    And the row with id "entry-001" still has outcome "succeeded"

  @security @happy
  Scenario: Attempt to DELETE an audit row triggers RAISE and fails
    Given an audit entry with id "entry-002" exists
    When code attempts "DELETE FROM cluster_mutation_audit WHERE id='entry-002'"
    Then the SQLite trigger raises an ABORT
    And the DELETE is rolled back
    And the row with id "entry-002" still exists in the table

  @happy @lifecycle
  Scenario: INSERT into cluster_mutation_audit succeeds normally (append is allowed)
    Given the application is writing a new audit entry after a successful delete mutation
    When a new row is inserted with a unique UUIDv7 id and outcome "succeeded"
    Then the INSERT completes without triggering any RAISE
    And the new row is readable via SELECT
    And the trigger fires only on UPDATE and DELETE, not on INSERT

  @security @lifecycle
  Scenario: Duplicate requestId INSERT is blocked by unique constraint before the trigger fires
    Given an audit entry with requestId "req-abc-123" already exists
    When the application attempts to insert another row with the same requestId
    Then the SQLite unique constraint on requestId rejects the INSERT with SQLITE_CONSTRAINT
    And no trigger is needed for this case (the unique constraint fires first)
    And the duplicate submission is detected before any API call is dispatched
