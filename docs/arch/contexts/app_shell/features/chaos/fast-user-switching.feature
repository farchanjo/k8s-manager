# DDD role: ChaosScenario
# Bounded context: app_shell
# Failure mode: fast-user-switching state isolation failure
# References: ADR-0041, ADR-0022, ADR-0027

Feature: Fast-user-switch keeps per-user app instances fully isolated
  As a macOS administrator
  I need each user's K8sManager instance to be isolated from other users' instances
  So that credentials, drafts, and cluster sessions are never shared across user boundaries

  Background:
    Given User A is the active macOS user with K8sManager running and connected to "prod-eu"
    And User B has K8sManager installed with their own kubeconfig and credential set

  @chaos @concurrency
  Scenario: Switching to User B starts an independent app instance with User B's home directory
    When the operator performs a fast-user-switch from User A to User B
    Then macOS activates User B's login session
    And if K8sManager launches for User B it reads config from "~B/.config/k8smanager/"
    And User B's app instance has NO access to User A's kubeconfigs, Keychain items, or drafts
    And User A's app instance continues running in its suspended session without data modification

  @chaos @concurrency
  Scenario: Switching back to User A restores the original session state
    Given User A was active with session "prod-eu" connected when the switch occurred
    When the operator switches back to User A
    Then User A's K8sManager resumes with the "prod-eu" session in whatever state it was left
    And no data from User B's session has been written to User A's data directory
    And the watch stream for "prod-eu" reconnects if it dropped during the suspended state

  @chaos @concurrency
  Scenario: Process lock files are per-user and do not conflict across accounts
    Given User A's instance holds a process lock at "/var/folders/<A>/k8smanager.lock"
    When User B's instance starts and checks for a running instance
    Then User B's instance looks for a lock in User B's own temp directory (not User A's)
    And User B's instance starts normally (not treating User A's lock as a conflict)
