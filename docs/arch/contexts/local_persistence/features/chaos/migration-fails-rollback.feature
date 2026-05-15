# DDD role: ChaosScenario
# Bounded context: local_persistence
# Failure mode: schema migration failure and safe rollback (F6 variant)
# References: ADR-0041, ADR-0027, ADR-0033

Feature: Failed schema migration rolls back without advancing schema_migrations table
  As a cluster operator
  I need the migration subsystem to roll back cleanly when a migration script throws
  So that subsequent app launches retry the migration rather than skipping it silently

  Background:
    Given the database schema is at version 16
    And migration script v17 is present but contains a deliberate error (invalid ALTER TABLE)

  @chaos @disk
  Scenario: Migration v17 throws and the transaction rolls back; schema stays at v16
    When the app launches and the migration runner executes v17
    Then the migration script throws during execution
    And the surrounding database transaction is rolled back
    And the "schema_migrations" table still records v16 as the latest applied version
    And no partial schema changes from v17 remain in the database

  @chaos @disk
  Scenario: App surfaces a migration failure notification and exits gracefully
    Given migration v17 has thrown and been rolled back
    When the app finalizes its startup sequence after the rollback
    Then the app surfaces "Database migration failed — the app will not start until the issue is resolved"
    And the app exits with a non-zero exit code
    And a log entry is written with the migration error details and version number

  @chaos @disk
  Scenario: Next launch retries migration v17 safely
    Given migration v17 failed in a prior launch and the schema is at v16
    And the migration script v17 has been corrected (simulated by replacing with a valid script)
    When the app launches again
    Then the migration runner retries v17
    And the migration succeeds
    And "schema_migrations" is updated to v17
    And the app starts normally

  @chaos @disk
  Scenario: A migration failure on a fresh install does not corrupt an empty database
    Given a fresh install with an empty SQLite database
    When migration v17 (the first migration) throws and rolls back
    Then the empty database has no tables or partial schema artifacts
    And the integrity check passes on the empty database
