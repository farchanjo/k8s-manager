# DDD role: ChaosScenario
# Bounded context: app_shell
# Failure mode: F18 variant (config directory on unreliable NFS/network volume)
# References: ADR-0041, ADR-0022, ADR-0027

Feature: Config directory on a network volume is rejected at startup with actionable prompt
  As a cluster operator
  I need the app to refuse to run when its data directory is on a network filesystem
  So that power-loss or network interruption cannot silently corrupt the SQLite WAL

  Background:
    Given "~/.config/k8smanager/" is a symlink pointing to "/Volumes/nfs-home/k8smanager/"
    And the NFS mount is live and accessible

  @chaos @disk
  Scenario: App detects network filesystem via statfs and refuses to start
    When the app starts and evaluates the data directory path
    Then the app calls statfs (or equivalent) on the resolved path
    And statfs indicates the filesystem type is NFS (or CIFS/SMB/AFP)
    And the app surfaces "Data directory is on a network volume — this is not supported"
    And the app exits with a non-zero exit code without initializing any database
    And the metric "startup_network_volume_rejected_total" increments by 1

  @chaos @disk
  Scenario: App prompts the operator to specify a local path before exiting
    Given the network-volume rejection has been detected
    When the error dialog is displayed
    Then the dialog includes the actionable message "Please choose a local directory in Settings or move ~/.config/k8smanager/ to local storage"
    And a "Open Settings" button is available that opens the path-selection UI
    And the operator can specify a local path without relaunching the app from the command line

  @chaos @disk
  Scenario: App starts normally when the data directory is on a local APFS or HFS+ volume
    Given "~/.config/k8smanager/" resolves to a local APFS volume
    When the app starts and evaluates the data directory path
    Then statfs reports a local filesystem type
    And the app proceeds with normal initialization
    And no rejection dialog is shown
