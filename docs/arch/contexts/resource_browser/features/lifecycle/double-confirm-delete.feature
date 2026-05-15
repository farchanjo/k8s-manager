# DDD role: BehaviouralSpecification
# Bounded context: resource_browser
# References: ADR-0012
# CUE schema: contexts/resource_browser/schemas/mutation_audit_entry.cue

Feature: Double-confirm delete for resources with finalizers
  As an operator
  I want the double-confirm flow to require typing the exact resource name before deleting
  So that accidental deletion of critical resources is prevented

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Pod named "worker-0" in namespace "batch" exists with a finalizer "batch.example.com/cleanup"

  @happy @lifecycle
  Scenario: Successful double-confirm delete with typed resource name
    Given the operator selects "worker-0" in the resource browser and chooses "Delete"
    When the first confirmation modal appears showing the Pod identity and finalizer warning
    And the operator presses "Confirm"
    Then the second confirmation modal appears requiring the operator to type "worker-0"
    When the operator types "worker-0" exactly and the action button becomes enabled
    And the operator presses the action button
    Then a DELETE request is dispatched to the API server for "worker-0" in namespace "batch"
    And an audit entry is written with verb "delete" and outcome "succeeded"
    And the resource browser removes "worker-0" from the pod list

  @failure @lifecycle
  Scenario: Typed name mismatch keeps the action button disabled
    Given the second confirmation modal is displayed for "worker-0"
    When the operator types "worker-00" (with a typo)
    Then the typed text does not match the resource name "worker-0"
    And the action button remains disabled
    And no DELETE request is dispatched
    When the operator corrects the text to "worker-0"
    Then the action button becomes enabled

  @failure @lifecycle
  Scenario: Cancel at the first confirmation modal writes a cancelled audit entry
    Given the operator selects "worker-0" and chooses "Delete"
    When the first confirmation modal appears
    And the operator presses "Cancel"
    Then no second confirmation modal is shown
    And no DELETE request is dispatched to the API server
    And an audit entry is written with outcome "cancelled"

  @failure @lifecycle
  Scenario: Delete with grace period 0 shows explicit force-delete warning
    Given the operator holds the Option key and chooses "Force Delete" for "worker-0"
    When the double-confirm modal appears
    Then the modal shows a prominent warning: "Force-delete bypasses the termination grace period — volumes may remain mounted"
    And the operator must type "worker-0" to proceed
    When the operator types "worker-0" and confirms
    Then the DELETE request includes the query parameter "gracePeriodSeconds=0"
    And the audit entry has verb "force-delete"
