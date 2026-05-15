# DDD role: Feature
# Bounded context: local_persistence
Feature: Store and retrieve persistent state

  As the application
  I want a single, durable store for non-secret state and a separate
  Keychain home for LLM API keys
  So that the assistant, settings surface, and diagnostics can read
  and write reliably and securely

  Background:
    Given the application has been launched on a fresh installation
    And the persistence layer has applied every numbered migration

  Scenario: First-launch initialises the database with WAL journal mode
    When the application opens the database for the first time
    Then a file exists at ~/Library/Application Support/com.archanjo.K8sManager/storage.sqlite3
    And PRAGMA journal_mode reports "wal"
    And PRAGMA foreign_keys reports 1
    And the schema_migrations table contains every shipped migration

  Scenario: A provider profile insert places the API key only in Keychain
    Given the operator saves a new provider profile with API key value V
    When the persistence layer commits the insert
    Then a row exists in provider_profiles with the matching key_alias
    And the row's columns do not contain V anywhere
    And a Keychain entry exists under service "com.archanjo.K8sManager.llm" with account equal to the key_alias
    And the Keychain entry stores V under accessControl "kSecAttrAccessibleWhenUnlockedThisDeviceOnly"

  Scenario: A redaction policy rejects an attempt to persist a bearer token
    Given a chat message body contains a JWT-shaped string
    When the persistence layer attempts to insert the message
    Then the insert is rejected with a redaction-policy violation
    And no row is added to chat_messages
    And a developer-facing log entry names the violating field

  Scenario: Concurrent readers do not starve the writer
    Given an assistant turn is streaming and writing tokens to chat_messages every 50 ms
    And the diagnostics panel is reading mcp_invocations every 100 ms
    When the operator opens the sidebar which reads provider_profiles and open sessions
    Then no reader blocks longer than 50 ms
    And the writer continues to advance turn_count without contention errors

  Scenario: Schema migration is applied exactly once
    Given a new migration "0003_add_cluster_analysis_cache" ships in the next release
    When the operator opens the new version
    Then the migration runs once inside a transaction
    And on next launch the migration is detected as already applied and skipped
    And the schema_migrations table records exactly one row per migration version

  Scenario: Deleting all local data clears both stores
    Given the persistent store contains sessions, profiles, and Keychain entries
    When the operator confirms "delete all local data" twice
    Then the SQLite file is removed
    And every Keychain entry under service "com.archanjo.K8sManager.llm" is removed
    And on next launch the application initialises a fresh database
