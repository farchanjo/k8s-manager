# DDD role: BehaviouralSpecification
# Bounded context: local_persistence
# References: ADR-0010, ADR-0019, ADR-0026

Feature: Schema migrations are applied exactly once per numbered version
  As a developer
  I want migrations to be idempotent and guarded by the schema_migrations table
  So that re-running the app after an update never re-applies an already-executed migration

  Background:
    Given "storage.sqlite3" is open at "~/.config/k8smanager/"
    And the "schema_migrations" table records applied migration version numbers

  @happy @lifecycle
  Scenario: Fresh database applies all migrations in order on first launch
    Given no "schema_migrations" table exists (fresh database)
    When the PersistenceActor runs the migration sequence on startup
    Then migrations 1 through N are applied in ascending order
    And each migration runs inside its own SQLite transaction
    And after each migration, a row is inserted into "schema_migrations" with the version number
    And the final schema matches the current in-code schema definition

  @idempotency @lifecycle
  Scenario: Re-running migrations on an up-to-date database applies none
    Given the "schema_migrations" table contains all version numbers from 1 through N
    When the PersistenceActor runs the migration sequence on startup
    Then GRDB's migration runner detects that all migrations have been applied
    And no migration SQL is executed
    And no new rows are inserted into "schema_migrations"
    And the startup completes without schema changes

  @failure @lifecycle
  Scenario: Migration fails mid-sequence — transaction is rolled back and app shows error
    Given migrations 1 through 4 have been applied successfully
    And migration 5 contains invalid SQL that will throw an error
    When the PersistenceActor runs the migration sequence
    Then migration 5's transaction is rolled back on error
    And migrations 6 through N are NOT attempted
    And the application surfaces an error: "Database migration failed at version 5 — please report this issue"
    And the database remains at version 4 (consistent with the last successful migration)

  @happy @lifecycle
  Scenario: Migration adding a new column is backward-compatible with existing rows
    Given migration 7 adds a column "isDraft BOOLEAN DEFAULT FALSE NOT NULL" to "editor_sessions"
    And the table already contains 10 rows from a previous version
    When migration 7 is applied
    Then the column is added with the DEFAULT value
    And all 10 existing rows have "isDraft" equal to FALSE
    And new rows can be inserted with either value for "isDraft"
