# DDD role: BehaviouralSpecification
# Bounded context: _shared (cross-cutting)
# References: ADR-0040, ADR-0005
# Rego policy: contexts/_shared/policies/event_bus_policy.rego
# CUE schema: contexts/_shared/schemas/domain_events.cue

Feature: DomainEventBusActor publish invariants — policy gate enforced before delivery
  As a platform engineer maintaining the shared event bus
  I want the DomainEventBusActor to enforce the event_bus_policy.rego rules on every
  publish() call before delivering an envelope to any subscriber
  So that unknown types, oversized payloads, mismatched contexts, and invalid envelopes
  are rejected at the boundary and never reach subscriber streams

  Background:
    Given the DomainEventBusActor is running and the event_bus_policy.rego is loaded
    And at least one subscriber is registered for "resource_browser.MutationApplied"
    And the policy default is deny — allow is true only when the deny set is empty

  @policy @invariant
  Scenario: Unknown event type rejected — not in known_event_types allowlist
    Given a bounded context attempts to publish an event with eventType "resource_browser.UnknownEvent"
    And the envelope has a valid eventId, occurredAt, sourceContext "resource_browser", and version 1
    And the payload size is 512 bytes
    When the DomainEventBusActor evaluates the event against event_bus_policy.rego
    Then the policy deny set contains a message matching "unknown event type"
    And the allow decision is false
    And the envelope is not delivered to any subscriber
    And no domain event reaches the subscriber's AsyncStream

  @policy @invariant
  Scenario: Payload over 4096 bytes rejected — oversized payload rule fires
    Given a bounded context attempts to publish "resource_browser.MutationApplied"
    And the envelope is otherwise valid (known type, matching sourceContext, version 1)
    And the payload.size field is 4097 bytes (one over the 4096-byte ceiling)
    When the DomainEventBusActor evaluates the event against event_bus_policy.rego
    Then the policy deny set contains a message matching "payload too large"
    And the allow decision is false
    And the envelope is not delivered to any subscriber

  @policy @invariant @boundary
  Scenario: Payload at exactly 4096 bytes accepted — boundary value passes policy
    Given a bounded context publishes "resource_browser.MutationApplied"
    And the payload.size is exactly 4096 bytes
    And the envelope is otherwise valid
    When the DomainEventBusActor evaluates the event
    Then the deny set is empty
    And the allow decision is true
    And the envelope is delivered to the registered subscriber

  @policy @invariant
  Scenario: sourceContext mismatch rejected — eventType prefix does not match sourceContext
    Given a bounded context attempts to publish eventType "helm_management.HelmRollbackInitiated"
    And the envelope sourceContext is "resource_browser" (mismatch — should be "helm_management")
    And the envelope eventId, occurredAt, and version 1 are valid
    And the payload.size is 256 bytes
    When the DomainEventBusActor evaluates the event against event_bus_policy.rego
    Then the policy deny set contains a message matching "does not match sourceContext"
    And the allow decision is false
    And the envelope is not delivered to any subscriber
    And the error is logged at level ERROR with the eventType and sourceContext values
