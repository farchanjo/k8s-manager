# DDD role: BehaviouralSpecification
# Bounded context: resource_browser
# References: ADR-0012, ADR-0030

Feature: Optimistic concurrency conflict resolution in the editor
  As an operator
  I want the editor to detect resourceVersion conflicts and let me resolve the diff manually
  So that my apply never silently overwrites concurrent changes made by another operator or controller

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Deployment "api-server" is open in the editor with resourceVersion "1001"
    And the operator has made local changes that set isDirty to true

  @failure @lifecycle
  Scenario: SSA PATCH returns 409 Conflict — editor shows merge banner
    Given another operator has patched "api-server" advancing its resourceVersion to "1005"
    When the operator confirms the apply
    Then a PATCH with fieldManager=com.archanjo.K8sManager is dispatched
    And the API server returns HTTP 409 Conflict
    And the adapter surfaces a #ConflictError event
    And the editor shows a merge banner "Conflict: cluster state changed (rv 1005) — resolve the diff"
    And the editor fetches the live manifest at resourceVersion "1005"
    And a three-pane diff view opens: "Your changes" | "Common ancestor" | "Cluster state"

  @happy @lifecycle
  Scenario: Operator resolves conflict and resubmits with new resourceVersion
    Given the three-pane conflict diff is displayed
    When the operator selects the "accept mine" resolution for the conflicting fields
    And clicks "Apply Resolved"
    Then the editor constructs a new manifest carrying resourceVersion "1005"
    And a new PATCH is dispatched with the merged content
    And the PATCH succeeds with HTTP 200
    And an audit entry is written with outcome "succeeded"
    And the editor returns to "idle" state

  @failure @lifecycle
  Scenario: Force ownership proceeds despite conflict when operator opts in
    Given the confirmation modal is showing a diff with conflicting field "spec.replicas"
    When the operator toggles "Force ownership — take over conflicting fields"
    And confirms the apply
    Then the PATCH is dispatched with the "force=true" query parameter
    And the audit entry records the force flag in the command payload
    And the editor shows a warning toast "Field ownership forced on spec.replicas"
