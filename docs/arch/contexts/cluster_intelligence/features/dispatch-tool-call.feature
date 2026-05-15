# DDD role: Feature
# Bounded context: cluster_intelligence
Feature: Dispatch an MCP tool call to the Kubernetes API

  As the assistant_chat context
  I want to execute a tool the model requested
  So that the assistant can produce grounded analysis based on the
  cluster's actual state

  Background:
    Given the in-process MCP server is running with the read-only registry
    And the active session is pinned to context "prod-east"
    And the connection pool for "prod-east" is warm

  Scenario: A registered tool with valid inputs succeeds
    Given a tool_use_finish arrives for "kube_list_pods" with arguments {"namespace":"default","limit":50}
    When the MCP server dispatches the invocation
    Then the policy gate allows the call
    And the invocation reaches the Kubernetes API server via the pooled HTTPClient
    And the outcome is "succeeded"
    And the resultJSON is a JSON object whose "items" array has length at most 50
    And an MCPInvocation record is persisted

  Scenario: A response larger than outputMaxBytes is truncated with a marker
    Given a tool_use_finish arrives for "kube_get_yaml" against a 700 KiB ConfigMap
    When the MCP server dispatches the invocation
    Then the outcome is "succeeded"
    And the resultJSON ends with "{\"_truncated\":true,\"_omittedBytes\":..."
    And the truncated boolean on the MCPInvocation is true
    And the resultBytes field reports the pre-truncation size

  Scenario: An unregistered tool is denied with rule "tool_not_registered"
    Given a tool_use_finish arrives for "kube_delete_pod"
    When the MCP server dispatches the invocation
    Then no HTTP request is made to the Kubernetes API server
    And the outcome is "denied_by_policy" with rule "tool_not_registered"
    And the host receives a tool_result that names the denial

  Scenario: An attempted mutating verb is denied
    Given a tool_use_finish arrives for a registered tool whose internal call would issue PATCH
    When the MCP server dispatches the invocation
    Then the outcome is "denied_by_policy" with rule "mutating_verb_forbidden"
    And no HTTP request is made to the Kubernetes API server

  Scenario: Inputs that fail JSON-Schema validation are rejected
    Given a tool_use_finish arrives for "kube_logs" with arguments {"namespace":"default","podName":""}
    When the MCP server attempts input validation
    Then the outcome is "denied_by_policy" with rule "inputs_invalid"
    And the host receives a tool_result that names the offending field

  Scenario: Cancellation aborts an in-flight invocation
    Given a tool_use_finish for "kube_logs" with follow=false is mid-stream
    When the host cancels the invocation
    Then the outcome is "cancelled"
    And the underlying HTTP request aborts within 200 milliseconds
    And no partial resultJSON is persisted
