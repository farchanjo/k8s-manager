# DDD role: ChaosScenario
# Bounded context: cluster_connectivity
# Failure mode: F10 (cluster CA rotation mid-session)
# References: ADR-0041, ADR-0025

Feature: Cluster CA bundle rotates while session is active
  As a cluster operator
  I need the adapter to detect TLS verification failures caused by CA rotation
  So that the user is guided to re-trust the new CA without losing the session state

  Background:
    Given a cluster session "prod-us" is established with a pinned CA bundle from kubeconfig
    And at least one LIST request has succeeded with TLS verified

  @chaos @cred
  Scenario: CA rotation causes next request to fail TLS; adapter re-reads kubeconfig
    Given the cluster administrator rotates the cluster CA
    When the adapter issues the next periodic health-probe request
    Then the TLS handshake fails with "certificate signed by unknown authority"
    And the adapter marks the session as "TLS-Degraded" without closing it
    And the adapter re-reads the kubeconfig file from disk to obtain the updated CA bundle
    And the adapter retries the health-probe with the new CA bundle

  @chaos @cred
  Scenario: Operator prompted to verify new CA fingerprint before session resumes
    Given the adapter has re-read the updated kubeconfig CA bundle
    And the new CA fingerprint differs from the pinned value
    When the adapter prepares to retry with the updated CA
    Then the UI surfaces a modal "Cluster CA has changed — verify fingerprint: <SHA256>"
    And the session is held in "TLS-Degraded" state until the operator confirms or rejects
    And confirming pins the new CA and resumes the session without data loss
    And rejecting closes the session with reason "ca-rotation-rejected"

  @chaos @cred
  Scenario: kubeconfig CA file absent after rotation leaves session in TLS-Degraded with clear error
    Given the cluster CA has rotated
    And the kubeconfig file on disk does not yet contain the new CA entry
    When the adapter re-reads the kubeconfig
    Then the adapter surfaces "CA bundle missing in kubeconfig — update kubeconfig to resume"
    And the session remains in "TLS-Degraded" state
    And no insecure TLS skip is applied under any condition
