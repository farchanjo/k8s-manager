# DDD role: Policy
package assistant_chat.chat_policy

# chat_policy.rego
#
# Governs LLM assistant tool invocations dispatched via the MCP host.
# Tool calls are read-only; cluster-mutating tools are explicitly denied.
# A per-session rate limit prevents unbounded tool invocation.
#
# input.toolName              — string: the MCP tool name being invoked
# input.toolCategory          — "read" | "mutate" | "unknown"
# input.sessionToolCallCount  — int: number of tool calls already made in
#                               this chat session
# input.rateLimit             — int: max tool calls per session (operator-
#                               configurable; default 60)
# input.mcpHostVerified       — bool: the tool is registered in the in-process
#                               MCP server (not an external arbitrary endpoint)

default allow := false

# ---------------------------------------------------------------------------
# Happy-path allow: read-only tool via verified MCP host, within rate limit
# ---------------------------------------------------------------------------

allow {
    input.toolCategory == "read"
    input.mcpHostVerified == true
    input.sessionToolCallCount < input.rateLimit
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_mutating_tool[msg] {
    input.toolCategory == "mutate"
    msg := sprintf(
        "tool %q is a cluster-mutating tool; the assistant context is read-only; mutating tools may only be invoked from the resource_browser context",
        [input.toolName]
    )
}

deny_unverified_mcp_host[msg] {
    input.mcpHostVerified == false
    msg := sprintf(
        "tool %q was not registered in the in-process MCP server; external or dynamically injected tools are not permitted",
        [input.toolName]
    )
}

deny_rate_limit_exceeded[msg] {
    input.sessionToolCallCount >= input.rateLimit
    msg := sprintf(
        "tool %q denied: session tool call count (%d) has reached the configured rate limit (%d); start a new chat session to continue",
        [input.toolName, input.sessionToolCallCount, input.rateLimit]
    )
}

deny_unknown_tool_category[msg] {
    input.toolCategory == "unknown"
    msg := sprintf(
        "tool %q has an unknown category; all tools must be classified as read or mutate before use",
        [input.toolName]
    )
}

# ---------------------------------------------------------------------------
# Negative test cases
#
# test_deny_mutating_tool:
#   input = {
#     "toolName": "k8s_apply_yaml",
#     "toolCategory": "mutate",
#     "sessionToolCallCount": 0,
#     "rateLimit": 60,
#     "mcpHostVerified": true
#   }
#   expect: allow == false
#   expect: deny_mutating_tool contains "cluster-mutating tool"
#
# test_deny_unverified_external_mcp_host:
#   input = {
#     "toolName": "external_tool",
#     "toolCategory": "read",
#     "sessionToolCallCount": 0,
#     "rateLimit": 60,
#     "mcpHostVerified": false
#   }
#   expect: allow == false
#   expect: deny_unverified_mcp_host contains "in-process MCP server"
#
# test_deny_rate_limit_exceeded:
#   input = {
#     "toolName": "k8s_list_pods",
#     "toolCategory": "read",
#     "sessionToolCallCount": 60,
#     "rateLimit": 60,
#     "mcpHostVerified": true
#   }
#   expect: allow == false
#   expect: deny_rate_limit_exceeded contains "rate limit"
# ---------------------------------------------------------------------------
