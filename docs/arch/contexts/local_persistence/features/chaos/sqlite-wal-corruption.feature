# DDD role: ChaosScenario
# Bounded context: local_persistence
# Failure mode: WAL truncation from simulated power loss (F6 variant)
# References: ADR-0041, ADR-0027, ADR-0033

Feature: WAL truncated mid-write by power loss; SQLite recovers from main database on next open
  As a cluster operator
  I need the app to recover automatically from a WAL truncated by power loss
  So that the database is usable on next launch even if the last few uncommitted writes are lost

  Background:
    Given the SQLite database "~/.config/k8smanager/db.sqlite" contains 100 committed drafts
    And writes 101–103 were in-flight in the WAL at the time of simulated power loss
    And the WAL file has been truncated to 0 bytes (simulating incomplete flush before power loss)

  @chaos @disk
  Scenario: App opens database successfully and recovers committed state from main DB file
    When the app launches after the simulated power loss
    Then SQLite opens the database using the main DB file (WAL is empty / ignored)
    And the database passes an integrity check (PRAGMA integrity_check returns "ok")
    And drafts 1–100 are fully available
    And drafts 101–103 are absent (lost in truncation) — this is expected and acceptable

  @chaos @disk
  Scenario: App reports lost drafts to the operator on launch
    Given SQLite recovered but detected that the WAL contained uncommitted writes
    When the app completes its startup sequence
    Then the app surfaces a non-blocking notification "Last session ended unexpectedly — some recent changes may not have been saved"
    And the notification lists any draft IDs that are no longer present (101–103)

  @chaos @disk
  Scenario: App accepts new writes normally after WAL-truncation recovery
    Given the app has recovered from WAL truncation and shown the notification
    When the operator creates a new draft (draft 104)
    Then the write succeeds and the draft is committed to the WAL
    And subsequent reads return draft 104 correctly
    And no further recovery warning is shown
