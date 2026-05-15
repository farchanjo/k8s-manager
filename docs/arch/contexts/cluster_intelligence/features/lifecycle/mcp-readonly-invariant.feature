# DDD role: BehaviouralSpecification
# Bounded context: cluster_intelligence
# References: ADR-0009, ADR-0012
# CUE schema: contexts/cluster_intelligence/schemas/mcp_tool_registry.cue
# Policy: contexts/cluster_intelligence/policies/tool_policy.rego

Feature: MCP tool inventory contains only read-only verbs — policy enforced default-deny
  As a security reviewer
  I want to verify that every registered MCP tool uses only read verbs
  So that the LLM assistant can never cause cluster mutations through the tool surface

  Background:
    Given the in-process MCP server is initialised
    And the tool registry is populated from the compile-time tool inventory

  @security @happy
  Scenario: Every registered tool in the MVP inventory has a read-only verb scope
    When all registered MCP tools are enumerated from the tool registry
    Then the tool list is exactly: kube_list_pods, kube_describe, kube_get_yaml, kube_events, kube_logs, kube_top_pods, kube_cluster_info
    And for each tool the tool_policy.rego policy evaluates allow=true for verb "get" or "list"
    And for each tool the policy evaluates allow=false for verbs "create", "patch", "delete", "apply", "scale", "exec"
    And no tool name contains the substrings "delete", "mutate", "apply", "scale", "patch", "restart", "evict", "cordon", "drain", or "finalize"

  @security @lifecycle
  Scenario: Attempting to register a mutating tool is blocked at server initialisation
    Given a developer attempts to add a tool "kube_delete_pod" to the tool registry
    When the MCP server validates the tool during startup
    Then the tool_policy.rego policy denies registration of any tool whose name implies a mutating verb
    And the server startup fails with a "mutating tool registration denied" error
    And no such tool is reachable at runtime

  @security @lifecycle
  Scenario: Default-deny policy blocks any tool call that was not explicitly registered
    When the LLM assistant generates a tool_use for "kube_list_nodes" (a valid but unregistered tool)
    Then the MCP host looks up "kube_list_nodes" in the registry
    And the tool is not found (default-deny: unregistered tools are denied, not silently ignored)
    And a tool_result error "tool not registered: kube_list_nodes" is returned
    And the conversation continues without any cluster API call

  @happy @lifecycle
  Scenario: Registered read tool passes policy gate and is dispatched to the cluster
    When "kube_list_pods" is invoked with namespace "default"
    Then the policy gate evaluates allow=true for verb "list" against resource "pods"
    And the KubernetesApiPort issues a GET /api/v1/namespaces/default/pods request
    And the result is returned to the MCP host as a UTF-8 JSON payload (up to 256 KiB)
