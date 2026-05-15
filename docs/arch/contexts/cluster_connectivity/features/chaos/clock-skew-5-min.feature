# DDD role: ChaosScenario
# Bounded context: cluster_connectivity
# Failure mode: F9 (client-clock skew causing TLS failure)
# References: ADR-0041, ADR-0025

Feature: Client clock 5 minutes ahead of cluster causes TLS validation failure
  As a cluster operator
  I need the app to detect clock-skew-induced TLS failures and guide me to fix them
  So that I am not left with a cryptic certificate error and no recovery path

  Background:
    Given a cluster "prod-eu" whose API server certificate has a 1-year validity window
    And the device system clock is set 5 minutes ahead of the cluster's NTP reference

  @chaos @clock
  Scenario: TLS validation fails due to clock skew and app surfaces human-readable prompt
    When the adapter attempts to establish a new session to "prod-eu"
    Then the TLS handshake fails with a certificate-time error
    And the adapter detects that the failure is consistent with clock skew
    And the UI surfaces the message "System clock differs from cluster time — sync your clock to continue"
    And the session is not opened
    And no insecure TLS skip is applied

  @chaos @clock
  Scenario: After operator syncs clock the session opens successfully
    Given the app has surfaced "System clock differs from cluster time"
    When the operator synchronizes the device clock via NTP
    And the operator retries the session connection
    Then the TLS handshake succeeds
    And the session is established in "Connected" state
    And the metric "session_tls_clock_skew_total" is not incremented on the successful retry

  @chaos @clock
  Scenario: Clock skew below 30 seconds does not trigger the clock-skew prompt
    Given the device system clock is 25 seconds ahead of the cluster NTP reference
    When the adapter establishes a session to "prod-eu"
    Then the TLS handshake succeeds without surfacing any clock warning
    And the session reaches "Connected" state normally
