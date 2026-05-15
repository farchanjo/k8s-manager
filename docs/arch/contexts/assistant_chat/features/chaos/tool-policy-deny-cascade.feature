# DDD role: ChaosScenario
# Bounded context: assistant_chat
# Failure mode: tool-policy denial cascade (all mutation paths blocked by OPA)
# References: ADR-0041, ADR-0031, ADR-0034

Feature: OPA policy denies all mutation tools and conversation continues with inline errors
  As a cluster operator
  I need the assistant to handle tool-policy denials gracefully
  So that blocked tool calls do not crash the conversation or leave it in an unknown state

  Background:
    Given the assistant chat is open
    And the tool_policy.rego rule "deny_all_mutations" is active and denies all write tools
    And the assistant has been asked to "scale the nginx deployment to 5 replicas"

  @chaos @cred
  Scenario: First mutation tool request is denied by OPA and assistant attempts alternate path
    When the assistant invokes the "scale_deployment" tool
    Then the tool policy evaluator rejects the call with reason "deny_all_mutations"
    And the rejection is surfaced inline in the conversation as a tool error
    And the assistant attempts an alternate approach (e.g., "patch_resource") without halting

  @chaos @cred
  Scenario: All alternate tool paths are denied and the assistant surfaces a coherent error
    Given "scale_deployment" was denied
    When the assistant subsequently invokes "patch_resource" and "apply_manifest"
    Then all three tool calls are denied by the OPA policy
    And the assistant does NOT loop on tool invocations indefinitely
    And the assistant surfaces the message "I cannot complete this action — all modification tools are blocked by policy"
    And the conversation remains in a valid, continuable state

  @chaos @cred
  Scenario: Operator can continue the conversation with read-only queries after full denial
    Given all mutation tools were denied and the assistant surfaced the policy error
    When the operator asks "Show me the current replica count for nginx"
    Then the assistant invokes a read-only tool (e.g., "get_resource")
    And the tool policy allows the read-only call
    And the assistant returns the current replica count successfully
