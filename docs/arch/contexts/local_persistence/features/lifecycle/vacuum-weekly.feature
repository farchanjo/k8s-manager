# DDD role: BehaviouralSpecification
# Bounded context: local_persistence
# References: ADR-0010, ADR-0026

Feature: Weekly VACUUM INTO sidecar with atomic swap
  As an operator
  I want the database to be vacuumed weekly to reclaim space from deleted rows
  So that the "storage.sqlite3" file does not grow indefinitely from accumulated audit rows

  Background:
    Given "storage.sqlite3" exists at "~/.config/k8smanager/" with WAL mode enabled
    And the last successful vacuum ran more than 7 days ago (recorded in a metadata row)

  @happy @lifecycle
  Scenario: Weekly vacuum runs on first launch after the 7-day threshold
    When the application launches and the weekly vacuum schedule check fires
    Then the PersistenceActor issues "VACUUM INTO '~/.config/k8smanager/storage.sqlite3.vacuum'"
    And the vacuum completes successfully writing a defragmented copy to the sidecar
    And the original "storage.sqlite3" is replaced atomically with the sidecar (rename(2))
    And the sidecar file is deleted after the rename
    And the metadata row recording the last vacuum time is updated to the current timestamp

  @failure @lifecycle
  Scenario: Vacuum fails due to insufficient disk space — original database is untouched
    Given available disk space is less than the current database size
    When the VACUUM INTO command runs
    Then the VACUUM INTO fails with SQLITE_FULL or similar error
    And the original "storage.sqlite3" is NOT replaced (the rename is never issued)
    And the partial sidecar file "storage.sqlite3.vacuum" is deleted if it exists
    And a log entry records "Weekly vacuum failed: insufficient disk space"
    And the last vacuum timestamp is NOT updated (the vacuum will be retried on the next launch)

  @happy @lifecycle
  Scenario: Vacuum schedule check does not run if threshold has not passed
    Given the last vacuum ran 3 days ago
    When the application launches and the schedule check fires
    Then the schedule check determines that 3 days < 7 days threshold
    And no VACUUM INTO is issued
    And the application continues with the normal startup sequence

  @lifecycle @happy
  Scenario: Log files older than 30 days are pruned during the weekly vacuum task
    Given log files exist for dates ranging from 35 days ago to yesterday
    When the weekly maintenance task runs alongside the vacuum
    Then log files older than 30 days are deleted from "~/.config/k8smanager/logs/"
    And log files within the last 30 days are retained
    And the deletion is performed after the vacuum completes (not before)
