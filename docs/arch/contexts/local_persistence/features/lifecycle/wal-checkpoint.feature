# DDD role: BehaviouralSpecification
# Bounded context: local_persistence
# References: ADR-0010, ADR-0026
# CUE schema: contexts/local_persistence/schemas/persistence_store.cue

Feature: WAL checkpoint triggers when WAL grows beyond threshold
  As an operator
  I want the SQLite WAL to be checkpointed automatically before it grows too large
  So that the WAL sidecar file does not consume unbounded disk space

  Background:
    Given the SQLite database is open at "~/.config/k8smanager/storage.sqlite3" with journal_mode=WAL
    And the PersistenceActor is the sole writer

  @happy @lifecycle
  Scenario: WAL exceeds configured page threshold and checkpoint is triggered
    Given the WAL file has grown beyond 1000 pages (approximately 4 MB at the default 4 KB page size)
    When the PersistenceActor writes the next batch to the WAL
    Then GRDB triggers an automatic WAL checkpoint (sqlite3_wal_hook)
    And the checkpoint transfers WAL pages to the main database file
    And the WAL file is truncated to zero (passive checkpoint if no readers block)
    And the checkpoint completes without blocking read connections

  @happy @lifecycle
  Scenario: Passive checkpoint allows readers to complete without blocking
    Given the WAL threshold is exceeded during a read-heavy period (resource list display)
    When the passive WAL checkpoint runs
    Then the checkpoint does not block active read connections
    And read connections continue to read committed data without interruption
    And the checkpoint completes as soon as all readers finish their current reads

  @failure @lifecycle
  Scenario: WAL checkpoint fails because another process holds a read lock
    Given an external process has a read lock on the WAL file
    When the passive checkpoint runs
    Then the checkpoint partially completes (uncheckpointed frames remain)
    And a log entry notes "WAL checkpoint incomplete — frames remaining: N"
    And the application continues operating normally with the partial checkpoint
    And the full checkpoint is deferred to the next trigger opportunity

  @lifecycle @happy
  Scenario: PRAGMA optimize runs on launch to maintain query planner statistics
    When the application launches and opens the SQLite connection
    Then the PersistenceActor executes "PRAGMA optimize" during the startup phase
    And the query planner statistics are updated
    And the PRAGMA completes before the first user-facing query runs
    And no migration runs are affected by the PRAGMA optimize call
