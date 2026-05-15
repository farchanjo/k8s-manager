# DDD role: ChaosScenario
# Bounded context: local_persistence
# Failure mode: F18 (ENOSPC — disk full on write)
# References: ADR-0041, ADR-0027, ADR-0033

Feature: ENOSPC on write triggers modal prompt and waits for operator to free space
  As a cluster operator
  I need the app to block gracefully on a full disk rather than crashing or corrupting state
  So that I can free disk space and resume without losing any in-flight data

  Background:
    Given the app's data directory "~/.config/k8smanager/" is on a volume with 0 bytes free
    And the app is attempting to write a new draft or update the WAL

  @chaos @disk
  Scenario: ENOSPC on write surfaces a blocking modal and suspends all writes
    When any write call to the SQLite database returns ENOSPC (error 28)
    Then the app surfaces a blocking modal "Disk full — free space to continue"
    And the modal cannot be dismissed without resolving the disk space issue
    And all write operations to the database are suspended
    And read operations (viewing existing data) remain available

  @chaos @disk
  Scenario: Operator frees disk space and app retries the failed write successfully
    Given the blocking modal "Disk full" is displayed
    When the operator frees at least 500 MB of disk space on the same volume
    And the operator clicks "Retry" in the modal
    Then the app re-attempts the suspended write
    And the write succeeds
    And the modal is dismissed
    And normal write operations resume without data loss or corruption

  @chaos @disk
  Scenario: Existing data is intact after a disk-full event and recovery
    Given a disk-full event occurred while writing a new draft
    When the operator frees space and the app retries
    Then all previously committed data (earlier drafts, settings, audit entries) is intact
    And no database corruption is detected on SQLite integrity check
    And the in-flight draft write either completes or is cleanly aborted with user notification
