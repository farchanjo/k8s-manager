# DDD role: BehaviouralSpecification
# Bounded context: terminal_session
# References: ADR-0012, ADR-0017

Feature: Privileged debug pod policy enforcement
  As a security-conscious operator
  I want the application to enforce that node debug pod creation follows the mutation policy
  So that privilege escalation via debug pods is subject to the same confirmation guards as other mutations

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And the operator attempts to open a node debug session for node "node-1"

  @security @lifecycle
  Scenario: Debug pod with privileged=true without confirmation is denied by mutation guard
    Given the operator skips or bypasses the confirmation modal via a direct API call
    When the MutationGuardPort evaluates the NodeDebugCreate command
    Then the guard denies the command because no confirmationToken is present
    And no Pod creation API call is dispatched
    And an audit entry is written with outcome "denied" and verb "create"

  @security @lifecycle
  Scenario: Debug pod creation proceeds only after confirmation modal is acknowledged
    Given the ADR-0012 confirmation modal is shown for the node debug Pod
    When the operator presses "Create Debug Pod"
    Then the confirmationToken is generated and the MutationGuardPort accepts the command
    And a POST request to create the Pod with hostNetwork=true, hostPID=true, privileged=true is dispatched
    And an audit entry is written with outcome "succeeded"
    And the TerminalSessionActor is spawned after the Pod reaches Running state

  @failure @lifecycle
  Scenario: Debug pod image pull failure surfaces an error and no session opens
    Given the confirmation modal was acknowledged and the Pod creation was dispatched
    When the Pod fails to pull the debug image (ImagePullBackOff after 60 seconds)
    Then the TerminalSessionActor detects the pod is not in Running state after the deadline
    And the session transitions to "error"
    And the Pod is deleted automatically to avoid orphan accumulation
    And the UI shows "Debug pod failed to start — image pull error"

  @security @lifecycle
  Scenario: Debug pod securityContext override is not accepted without explicit documentation
    Given the debug session uses a non-default image that requests securityContext.runAsNonRoot=true
    When the NodeDebugDescriptor is constructed with privileged=false
    Then the NodeDebugDescriptor schema marks privileged=false as valid and the audit entry records it
    And the confirmation modal explicitly shows "privileged: false" in the pod spec summary
