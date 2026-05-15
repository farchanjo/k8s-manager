# DDD role: ChaosScenario
# Bounded context: resource_browser
# Failure mode: F4 (aggregated API server unavailable during mutation)
# References: ADR-0041, ADR-0023, ADR-0030

Feature: Mutation against CRD backed by down aggregated API server returns 503
  As a cluster operator
  I need mutations to CRDs backed by an aggregated API server to fail cleanly
  So that the audit log captures the failure and the UI provides a clear error path

  Background:
    Given the resource browser has the CRD "Widget.chaos.example.com" listed
    And the aggregated API server responsible for "chaos.example.com" is down
    And the editor has an unsaved Widget manifest ready for apply

  @chaos @network
  Scenario: Apply to a CRD with aggregated API server down produces 503 and audit failure entry
    When the operator clicks "Apply" on the Widget manifest
    Then the API server proxy returns HTTP 503 Service Unavailable
    And the mutation is aborted
    And an audit entry is written with status "failed" and reason "aggregated-api-503"
    And the UI surfaces "Apply failed — extended API server unavailable (503)"

  @chaos @network
  Scenario: The operator can navigate and LIST other native resources while the aggregated API is down
    Given the Widget mutation returned 503
    When the operator navigates to "Deployments" in the same namespace
    Then the LIST for Deployments succeeds
    And the resource browser displays the Deployment list without error
    And no residual error state from the Widget failure is shown in the Deployment view

  @chaos @network
  Scenario: Apply succeeds when the aggregated API server recovers without editor reload
    Given the aggregated API server for "chaos.example.com" has recovered
    And the operator has NOT closed the editor
    When the operator clicks "Apply" again on the same Widget manifest
    Then the API server returns HTTP 201 Created
    And an audit entry is written with status "success"
    And the editor shows the applied manifest in read mode
