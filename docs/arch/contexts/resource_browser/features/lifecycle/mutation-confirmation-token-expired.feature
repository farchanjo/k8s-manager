# DDD role: BehaviouralSpecification
# Bounded context: resource_browser
# References: ADR-0012, ADR-0030
# CUE schema: contexts/resource_browser/schemas/mutation_audit_entry.cue

Feature: Mutation confirmation token expiry
  As an operator
  I want stale confirmation tokens to be rejected so that delayed or replayed applies are blocked
  So that an operator cannot inadvertently apply a manifest reviewed minutes ago against a changed cluster state

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And a Deployment "api-server" is open in the editor with a pending apply
    And the confirmation modal has been displayed and a confirmationToken (UUIDv7) was generated at T=0

  @failure @lifecycle
  Scenario: Token rejected when operator delays apply beyond 300 seconds
    Given 305 seconds have elapsed since the confirmationToken was issued at T=0
    When the operator presses the Apply button
    Then the MutationGuardPort rejects the command with reason "confirmation-token-expired"
    And no PATCH request is dispatched to the Kubernetes API server
    And an audit entry is written with outcome "denied" and kubernetesStatusCode null
    And the editor surfaces a toast "Confirmation expired — please review the diff and confirm again"
    And the editor state returns to "dryRunComplete" (the diff preview is still visible)

  @happy @lifecycle
  Scenario: Token accepted when operator confirms within the valid window
    Given 60 seconds have elapsed since the confirmationToken was issued at T=0
    When the operator presses the Apply button
    Then the MutationGuardPort accepts the token (within 300-second validity window)
    And a PATCH with fieldManager=com.archanjo.K8sManager is dispatched to the API server
    And an audit entry is written with outcome "succeeded"
    And the editor state transitions to "applied"

  @idempotency @lifecycle
  Scenario: Duplicate requestId is rejected before API call is dispatched
    Given a first apply succeeded and its requestId "req-abc-123" is recorded in "cluster_mutation_audit"
    When the same MutationCommand with requestId "req-abc-123" is submitted a second time
    Then the MutationGuardPort detects the duplicate requestId
    And the command is rejected with reason "duplicate-request-id"
    And no second PATCH request is dispatched to the API server
    And the existing audit entry for "req-abc-123" is not modified

  @failure @lifecycle
  Scenario: resourceVersion conflict during apply prompts operator to refresh
    Given the operator applies a manifest with resourceVersion "1001"
    And the cluster has since advanced that resourceVersion to "1005"
    When the API server returns HTTP 409 Conflict
    Then the adapter surfaces a #ConflictError event to the editor
    And the editor shows a banner "Resource version conflict — the cluster state has changed since you opened this manifest"
    And a "Refresh" button re-fetches the live manifest into the editor buffer
    And the apply is not retried automatically
