# DDD role: ChaosScenario
# Bounded context: resource_browser
# Failure mode: F17 (audit log integrity violation)
# References: ADR-0041, ADR-0024, ADR-0030, ADR-0047

Feature: Corrupted audit entry digest halts new audit writes
  As a cluster operator
  I need the audit subsystem to detect tampered entries and freeze writes
  So that audit trail integrity is preserved and no further entries corrupt the chain

  Background:
    Given the cluster_mutation_audit store contains 50 valid entries
    And each entry carries a valid HMAC-SHA256 "previous_entry_digest" linking the chain
    And the HMAC key is present in the macOS Keychain under account "chain-mac-key-v1"

  @chaos @io
  Scenario: Injected digest corruption triggers integrity failure and red banner
    Given a test fixture corrupts entry #48's "previous_entry_digest" field directly in SQLite
    When the audit verification pass runs (triggered on next mutation or on app resume)
    Then the ChainVerifier recomputes the HMAC-SHA256 tag for entry #48 and finds a mismatch
    And the UI displays a red persistent banner "Audit integrity check failed — chain broken at entry #48"
    And the banner is not dismissible without an explicit operator action

  @chaos @io
  Scenario: No new audit entries are accepted while the chain is broken
    Given the audit integrity check has failed at entry #48
    When the operator applies a manifest (which would normally produce an audit entry)
    Then the mutation is rejected with "Audit log integrity compromised — writes suspended"
    And the mutation is not forwarded to the API server
    And the metric "audit_writes_suspended_total" increments by 1

  @chaos @io
  Scenario: Operator exports and resets the audit log to resume writes
    Given the audit chain is broken and writes are suspended
    When the operator clicks "Export audit log" and then "Reset audit chain"
    Then the full audit log (including the corrupted entry) is exported to a local file
    And the audit store is cleared and a new genesis entry is written with a fresh HMAC-SHA256 key
    And new audit entries are accepted after the reset
    And the red banner is cleared

  @chaos @io
  Scenario: Other release operations are unaffected while audit writes are suspended
    Given audit writes are suspended due to an integrity failure
    When the operator navigates to a different namespace and performs a LIST
    Then the LIST succeeds without any error
    And read-only operations are not blocked by the audit suspension

  @chaos @keychain
  Scenario: HMAC key absent from Keychain marks prior chain as unverifiable
    Given the Keychain item "chain-mac-key-v1" has been deleted (Keychain wipe simulation)
    When the app launches and AuditChainKeyManager attempts to load the key
    Then AuditChainKeyManager generates a new 256-bit key and stores it as "chain-mac-key-v1"
    And the prior 50 audit entries are marked "unverifiable" (prior key lost)
    And a new genesis entry with sentinel "0" * 64 is written using the new key
    And the UI displays a persistent warning "Audit chain reset — prior entries unverifiable (Keychain key was absent)"
    And new mutations produce verifiable entries under the new key

  @chaos @keychain
  Scenario: HMAC verification rejects a tampered entry and suspends writes
    Given the HMAC key is present and the chain has 50 valid entries
    And a test fixture modifies the "verb" field of entry #30 directly in SQLite without updating the HMAC digest
    When the ChainVerifier re-verifies entry #30 on the next mutation write
    Then HMAC-SHA256(key, prevDigestHex || canonicalJSON_of_entry_30) does not match entry #30's stored digest
    And the chain is marked corrupt at entry #30
    And the UI displays the red banner "Audit integrity check failed — chain broken at entry #30"
    And writes are suspended with reason "hmac_verify_failed"

  @chaos @keychain
  Scenario: Keychain locked at verification time pauses the chain without marking it corrupt
    Given the HMAC key exists in Keychain but the macOS screen is locked
    And the Keychain returns errSecInteractionNotAllowed when AuditChainKeyManager attempts to read the key
    When a mutation is submitted and ChainVerifier tries to verify the preceding entry
    Then ChainVerifier cannot retrieve the key and marks the chain as "paused"
    And the mutation is held (not rejected, not forwarded) until the chain resumes
    And the UI displays "Audit chain paused — Keychain locked. Unlock to resume verification."
    And after the operator unlocks the device the chain resumes and the held mutation is processed normally
