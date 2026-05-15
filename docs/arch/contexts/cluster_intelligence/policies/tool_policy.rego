# DDD role: Policy
package cluster_intelligence.tool_policy

import future.keywords.every
import future.keywords.in

#
# The MCP server delegates every tool invocation through these rules
# BEFORE issuing any HTTP request to a Kubernetes API server. A deny
# decision short-circuits the call with an OutcomeDeniedByPolicy
# carrying the matching rule identifier.

# Default: deny unless explicitly allowed.
default allow := false

# Allow only when every check passes.
allow {
    tool_registered
    no_mutating_verbs
    resources_allowed
    namespace_constraints_ok
    inputs_validated
}

# ---------- Individual rules ----------

# rule: tool_not_registered
# The MCP server short-circuits unknown tool names before this rule
# fires, but we keep an explicit check for defence in depth.
tool_registered {
    some i
    input.registry.tools[i].name == input.invocation.toolName
}

# rule: mutating_verb_forbidden
# The closed set of allowed verbs is exactly {get, list, watch}.
no_mutating_verbs {
    every v in input.invocation.requestedVerbs {
        v in {"get", "list", "watch"}
    }
}

# rule: resource_not_allowed
# Each tool declares the resource kinds it may touch; the invocation
# MUST resolve to one of those kinds.
resources_allowed {
    some i
    tool := input.registry.tools[i]
    tool.name == input.invocation.toolName
    some j
    tool.resources[j] == input.invocation.resolvedResource
}

# rule: namespace_must_be_present_for_namespaced_kinds
# Listing pods/events/logs across all namespaces is explicitly
# allowed for the observation use case, but per-tool documentation
# can require a namespace by setting `requiresNamespace: true` in
# the tool's metadata (carried in input.tool.requiresNamespace).
namespace_constraints_ok {
    not input.tool.requiresNamespace
}

namespace_constraints_ok {
    input.tool.requiresNamespace
    input.invocation.namespace != ""
}

# rule: inputs_validated
# The MCP server validates inputs against the tool's JSON Schema
# before evaluating this policy; we re-assert the boolean here so
# the policy file documents the dependency.
inputs_validated {
    input.invocation.inputsValid == true
}

# ---------- Reasons surfaced when deny fires ----------

deny_reason["tool_not_registered"] {
    not tool_registered
}

deny_reason["mutating_verb_forbidden"] {
    tool_registered
    not no_mutating_verbs
}

deny_reason["resource_not_allowed"] {
    tool_registered
    no_mutating_verbs
    not resources_allowed
}

deny_reason["namespace_required"] {
    tool_registered
    no_mutating_verbs
    resources_allowed
    not namespace_constraints_ok
}

deny_reason["inputs_invalid"] {
    tool_registered
    no_mutating_verbs
    resources_allowed
    namespace_constraints_ok
    not inputs_validated
}
