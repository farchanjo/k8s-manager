# DDD role: ChaosScenario
# Bounded context: local_persistence
# Failure mode: F6 (WAL file grows to limit, blocking writes)
# References: ADR-0041, ADR-0027, ADR-0033

Feature: WAL growth to 100 MB triggers forced checkpoint and controlled pause
  As a cluster operator
  I need the app to handle WAL saturation without data loss or silent write failure
  So that the WAL limit does not cause an opaque crash or corrupt database state

  Background:
    Given the SQLite WAL file at "~/.config/k8smanager/db.sqlite-wal" exists
    And the WAL size monitor runs on a 5-second interval

  @chaos @disk
  Scenario: WAL reaches 100 MB threshold and a blocking dialog is surfaced
    Given the WAL size is growing due to high write activity (simulated by large draft writes)
    When the WAL size reaches 100 MB
    Then the app detects the threshold breach on the next monitor tick (within 10 seconds)
    And the app surfaces a blocking dialog "Database maintenance required — performing checkpoint"
    And all new write operations are suspended until the checkpoint completes

  @chaos @disk
  Scenario: Forced checkpoint truncates the WAL and writes resume
    Given the blocking dialog "Database maintenance required" is shown
    When the app executes PRAGMA wal_checkpoint(TRUNCATE)
    Then the checkpoint completes successfully
    And the WAL file is truncated to under 1 MB
    And the blocking dialog is dismissed
    And normal write operations resume without data loss
    And the metric "wal_checkpoint_forced_total" increments by 1

  @chaos @disk
  Scenario: Checkpoint failure surfaces an error and leaves the app in read-only mode
    Given the forced checkpoint attempt fails (simulated by making the WAL file read-only)
    When the checkpoint returns SQLITE_BUSY or an IO error
    Then the app surfaces "Checkpoint failed — database is in read-only mode"
    And write operations remain suspended
    And read-only operations (browsing, listing) continue unaffected
    And a log entry is written with the checkpoint error code
