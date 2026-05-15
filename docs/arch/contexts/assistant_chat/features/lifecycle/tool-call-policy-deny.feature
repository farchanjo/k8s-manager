# DDD role: BehaviouralSpecification
# Bounded context: assistant_chat
# References: ADR-0009, ADR-0012
# CUE schema: contexts/cluster_intelligence/schemas/mcp_invocation.cue

Feature: Tool call denied by policy — conversation continues after tool error
  As an operator
  I want the assistant to receive a typed error when a tool call is blocked by policy
  So that the conversation continues gracefully and the assistant can explain the limitation

  Background:
    Given a ClusterSessionActor for "prod-us-east-1" is in "connected" state
    And an assistant chat session is open in read-only mode
    And the MCP tool registry contains only read tools: kube_list_pods, kube_describe, kube_get_yaml, kube_events, kube_logs, kube_top_pods, kube_cluster_info

  @security @lifecycle
  Scenario: Assistant requests kube_delete_pod — tool not registered — error returned
    When the LLM assistant generates a tool_use block for "kube_delete_pod"
    Then the MCP host looks up "kube_delete_pod" in the tool registry
    And the registry returns "tool not registered" because no mutating tools are registered
    And the error is serialised as a tool_result message and inserted into the conversation
    And the next assistant turn receives the error and generates a response explaining the limitation
    And the conversation continues without any mutation being dispatched to the cluster

  @security @lifecycle
  Scenario: Tool_policy.rego denies a read tool invoked with mutating parameters
    Given a future tool "kube_patch_resource" is registered but the policy denies it in read-only mode
    When the assistant requests "kube_patch_resource" with a PATCH body
    Then the tool_policy.rego policy gate evaluates the request
    And the policy returns a deny decision because the verb "patch" is not in the read-only allow-set
    And a tool_result error "Policy denied: verb patch not permitted in read-only mode" is returned to the assistant
    And no PATCH request is dispatched to the cluster

  @failure @lifecycle
  Scenario: Tool call with invalid JSON schema input is rejected before policy gate
    When the assistant generates a tool_use for "kube_list_pods" with a parameter "namespace" of type integer (invalid)
    Then the MCP host validates the input against the tool's JSON schema
    And validation fails with "namespace must be a string"
    And a tool_result error is returned to the assistant without reaching the policy gate
    And the conversation continues

  @happy @lifecycle
  Scenario: Valid read tool call succeeds and result is returned to the assistant
    When the assistant generates a tool_use for "kube_list_pods" with namespace "default"
    Then the tool_policy.rego policy allows the request (verb "list" is in the allow-set)
    And the MCP server calls kube_list_pods against the cluster via KubernetesApiPort
    And the result is returned as a tool_result to the assistant (up to 256 KiB)
    And the assistant uses the result to answer the operator's question
