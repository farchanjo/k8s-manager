# DDD role: BehaviouralSpecification
# Bounded context: cluster_intelligence
# References: ADR-0009
# CUE schema: contexts/cluster_intelligence/schemas/mcp_invocation.cue

Feature: Large MCP tool responses are truncated at 256 KiB with a truncation marker
  As an operator
  I want very large tool responses to be truncated rather than causing OOM or context overflow
  So that the assistant can still provide useful information even when a resource is enormous

  Background:
    Given the in-process MCP server is running
    And the maximum tool response body is 256 KiB (262144 bytes)

  @happy @lifecycle
  Scenario: kube_get_yaml on a huge ConfigMap is truncated at 256 KiB with a marker
    Given a ConfigMap "huge-config" in namespace "default" has 1 MB of data
    When the assistant calls "kube_get_yaml" for "huge-config"
    Then the MCP server fetches the ConfigMap YAML (1 MB) from the Kubernetes API
    And truncates the response at exactly 262144 bytes
    And appends {"_truncated": true, "_omittedBytes": <remaining bytes count>} to the end of the payload
    And returns the truncated payload to the MCP host as a tool_result
    And the assistant receives the truncation marker and can inform the operator that the resource is too large to display in full

  @failure @lifecycle
  Scenario: Tool response is empty — empty result returned without truncation marker
    Given a Deployment "empty-env" in namespace "default" has no environment variables
    When the assistant calls "kube_get_yaml" for "empty-env"
    Then the full YAML is returned (less than 1 KiB)
    And the truncation marker is NOT appended (no truncation occurred)
    And "_truncated" is absent from the tool_result payload

  @happy @lifecycle
  Scenario: kube_logs on a high-volume pod is truncated at 256 KiB
    Given a Pod "log-machine" has emitted 500 KiB of logs since its start
    When the assistant calls "kube_logs" for "log-machine" with tailLines=1000
    Then the log response is truncated at 262144 bytes
    And the truncation marker indicates the number of omitted bytes
    And the assistant receives the most recent log lines up to the budget

  @security @lifecycle
  Scenario: MCP wire log entry for a truncated response does not log the raw payload
    Given "kube_get_yaml" for "huge-config" returned a truncated 256 KiB payload
    When the MCP wire log entry is written to "storage.sqlite3"
    Then the wire log stores only the invocation metadata (tool name, duration, truncation flag)
    And the raw 256 KiB payload is NOT stored in the SQLite database
    And the log entry size is bounded and predictable
