# DDD role: ChaosScenario
# Bounded context: helm_management
# Failure mode: F16 (Helm Secret gzip payload corrupted / undecodable)
# References: ADR-0041, ADR-0030

Feature: Corrupted Helm Secret payload marks release Unreadable without affecting others
  As a cluster operator
  I need the Helm release reader to gracefully handle a corrupted Secret payload
  So that one broken release does not prevent me from viewing or operating others

  Background:
    Given namespace "production" contains 4 Helm releases: "my-app", "redis", "postgres", "nginx"
    And the Kubernetes Secret for release "my-app" revision 5 has a corrupted gzip payload
    (payload bytes 100-200 were overwritten with zeroes simulating partial storage failure)

  @chaos @disk
  Scenario: Corrupted Secret payload causes release "my-app" to be marked Unreadable
    When the Helm release list is loaded for namespace "production"
    Then the gzip decode of the "my-app" revision 5 Secret fails
    And "my-app" is listed with status "Unreadable" in the release browser
    And a log entry is written: "helm-secret-decode-failure release=my-app revision=5 error=gzip"
    And no error is propagated to the other releases

  @chaos @disk
  Scenario: Other releases in the namespace are fully readable despite the corruption
    Given "my-app" is marked "Unreadable"
    When the operator views the release list
    Then "redis", "postgres", and "nginx" are displayed with their correct statuses
    And rollback and upgrade actions remain available for the healthy releases
    And no blanket error banner covers the release browser

  @chaos @disk
  Scenario: Operator can trigger a rollback to a different revision whose Secret is intact
    Given the "my-app" revision 5 Secret is corrupted but revision 4 Secret is healthy
    When the operator selects "my-app" and chooses "Roll back to revision 4"
    Then the rollback proceeds using the intact revision 4 payload
    And the rollback succeeds and "my-app" is marked with the revision 4 manifests
    And a new Secret is written for revision 6 containing the applied manifests
