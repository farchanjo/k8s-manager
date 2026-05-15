# DDD role: ChaosScenario
# Bounded context: resource_browser
# Failure mode: F11 (optimistic-concurrency conflict on manifest apply)
# References: ADR-0041, ADR-0023, ADR-0030

Feature: Optimistic-concurrency 409 on manifest apply triggers diff-and-reapply flow
  As a cluster operator
  I need the editor to handle a 409 Conflict response gracefully
  So that I never silently overwrite a concurrent change made by another actor

  Background:
    Given the integrated editor is open with a "Deployment/nginx" manifest loaded
    And the manifest's resourceVersion is "1042" as fetched from the cluster
    And a concurrent actor has updated the Deployment to resourceVersion "1043" in the cluster

  @chaos @concurrency
  Scenario: Apply with stale resourceVersion returns 409 and editor presents diff
    When the operator clicks "Apply" with the locally-edited manifest (RV "1042")
    Then the API server returns HTTP 409 Conflict with "the object has been modified"
    And the editor automatically re-fetches the current manifest at RV "1043"
    And the editor presents a three-pane diff: "Your changes | Cluster state | Merged"
    And the "Apply" button is disabled until the operator resolves the diff

  @chaos @concurrency
  Scenario: Operator accepts the merge and re-applies successfully
    Given the diff view is displayed after a 409 response
    When the operator selects "Accept merge" and clicks "Apply"
    Then the apply request is issued with resourceVersion "1043"
    And the API server returns HTTP 200 OK
    And the editor clears the diff view and shows the saved manifest
    And the audit log records "apply-after-conflict-resolution" for this resource

  @chaos @concurrency
  Scenario: Operator discards local changes after 409 to accept the cluster state
    Given the diff view is displayed after a 409 response
    When the operator selects "Discard my changes"
    Then the editor loads the cluster's current manifest (RV "1043") without modification
    And no apply request is issued
    And the diff view is dismissed
