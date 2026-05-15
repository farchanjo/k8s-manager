# DDD role: ChaosScenario
# Bounded context: local_persistence
# Failure mode: F7 (macOS Keychain locked — errSecInteractionNotAllowed)
# References: ADR-0041, ADR-0027

Feature: Keychain read fails with errSecInteractionNotAllowed when device is locked
  As a cluster operator
  I need the app to handle a locked Keychain gracefully
  So that I am prompted to unlock rather than receiving a cryptic error or silent failure

  Background:
    Given the app holds a cached cluster credential reference in the Keychain
    And the macOS device has been locked (screen locked or fast-user-switch)

  @chaos @cred
  Scenario: Keychain read returns errSecInteractionNotAllowed and app shows unlock prompt
    When the app attempts to read a cluster credential from the Keychain
    Then the Keychain API returns error code -25308 (errSecInteractionNotAllowed)
    And the app does NOT crash or produce a silent failure
    And the UI surfaces the message "Unlock to continue — your device is locked"
    And all cluster operations requiring credentials are suspended

  @chaos @cred
  Scenario: After device unlock the app retries the Keychain read and resumes normally
    Given the "Unlock to continue" prompt is shown
    When the operator unlocks the device
    And the operator clicks "Continue" or the app auto-retries on foreground resume
    Then the Keychain read succeeds
    And the credential is used to resume the pending cluster operation
    And the unlock prompt is dismissed

  @chaos @cred
  Scenario: Read-only UI operations that do not require Keychain access continue while device is locked
    Given the device is locked and the Keychain is unavailable
    When the operator views previously cached resource data (e.g., a resource list loaded before the lock)
    Then the cached data is displayed without error
    And no Keychain access is attempted for the read-only display
