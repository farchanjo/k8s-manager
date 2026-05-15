# DDD role: Policy
# package _shared.event_bus_policy
#
# OPA policy gate for DomainEventBusActor (ADR-0040).
# Evaluated before publish() delivers an envelope to the registry.
#
# Input shape (all fields required):
#   input.eventType   — string, e.g. "resource_browser.MutationApplied"
#   input.envelope    — object matching #EventEnvelope (ADR-0040 / domain_events.cue)
#   input.payload     — object; the event-specific payload map
#   input.payload.size — integer byte count of the serialised payload
#
# Default: deny. Publish is allowed only when the deny set is empty.

package _shared.event_bus_policy

import rego.v1

# ---------------------------------------------------------------------------
# Allowlist of known event types (normative source: domain_events.cue).
# Extend this list whenever a new event type is added to domain_events.cue.
# ---------------------------------------------------------------------------

known_event_types := [
    # cluster_connectivity
    "cluster_connectivity.ClusterSessionOpened",
    "cluster_connectivity.ClusterSessionClosed",
    "cluster_connectivity.ClusterSessionDegraded",
    "cluster_connectivity.WatchStreamReconnected",
    "cluster_connectivity.WatchStreamDropped",
    # resource_browser
    "resource_browser.MutationApplied",
    "resource_browser.MutationFailed",
    "resource_browser.DraftSaved",
    "resource_browser.DraftPruned",
    # local_persistence
    "local_persistence.AuditEntryAppended",
    # port_forwarding
    "port_forwarding.PortForwardEstablished",
    "port_forwarding.PortForwardClosed",
    # terminal_session
    "terminal_session.TerminalSessionOpened",
    "terminal_session.TerminalSessionClosed",
    # helm_management
    "helm_management.HelmRollbackInitiated",
    "helm_management.HelmManifestApplied",
    "helm_management.HelmRollbackCompleted",
    # cluster_intelligence
    "cluster_intelligence.ToolInvoked",
    # app_shell
    "app_shell.DiagnosticsCollected",
    "app_shell.LocaleChanged",
    "app_shell.ThemeChanged",
    "app_shell.PreferencesUpdated",
    "app_shell.ContextSwitched",
    # domain_event_bus meta
    "domain_event_bus.DomainEventDropped",
]

# ---------------------------------------------------------------------------
# Default: deny all. Publish is allowed only when deny is empty.
# ---------------------------------------------------------------------------

default allow := false

allow if {
    count(deny) == 0
}

# ---------------------------------------------------------------------------
# Rule: reject unknown event types.
# ---------------------------------------------------------------------------

deny contains msg if {
    not input.eventType in known_event_types
    msg := sprintf("unknown event type: %q — add to known_event_types in event_bus_policy.rego and domain_events.cue", [input.eventType])
}

# ---------------------------------------------------------------------------
# Rule: reject oversized payloads.
# Bound: 4096 bytes serialised. Prevents runaway event payloads from
# exhausting the per-subscriber AsyncStream buffer memory (ADR-0040).
# ---------------------------------------------------------------------------

deny contains msg if {
    input.payload.size > 4096
    msg := sprintf("event payload too large: %d bytes (max 4096) for event type %q", [input.payload.size, input.eventType])
}

# ---------------------------------------------------------------------------
# Rule: reject unsupported envelope versions.
# Only version 1 is understood by the current bus implementation (ADR-0040).
# Consumers must reject versions they do not understand.
# ---------------------------------------------------------------------------

deny contains msg if {
    input.envelope.version != 1
    msg := sprintf("unsupported envelope version: %d (only version 1 is accepted)", [input.envelope.version])
}

# ---------------------------------------------------------------------------
# Rule: sourceContext in envelope must match the prefix of eventType.
# This prevents a bounded context from emitting events attributed to another.
# E.g. envelope.sourceContext="resource_browser" but eventType="helm_management.X"
# is rejected.
# ---------------------------------------------------------------------------

deny contains msg if {
    expected_prefix := concat(".", [input.envelope.sourceContext, ""])
    not startswith(input.eventType, expected_prefix)
    msg := sprintf(
        "eventType %q does not match sourceContext %q — eventType must begin with \"<sourceContext>.\"",
        [input.eventType, input.envelope.sourceContext],
    )
}

# ---------------------------------------------------------------------------
# Rule: eventId must be non-empty.
# A missing or empty eventId prevents deduplication and audit correlation.
# ---------------------------------------------------------------------------

deny contains msg if {
    count(input.envelope.eventId) == 0
    msg := "envelope.eventId must be a non-empty UUIDv7 string"
}

# ---------------------------------------------------------------------------
# Rule: occurredAt must be non-empty.
# ---------------------------------------------------------------------------

deny contains msg if {
    count(input.envelope.occurredAt) == 0
    msg := "envelope.occurredAt must be a non-empty RFC 3339 timestamp"
}

# ---------------------------------------------------------------------------
# Subscriber ACL (ADR-0040 "Read model dependency map").
# Maps subscriber bounded context → set of event types it is permitted to
# receive. Any subscription outside this table is denied.
#
# Source of truth: ADR-0040 §"Read model dependency map".
# Extend this table whenever a new subscriber relationship is established.
# ---------------------------------------------------------------------------

subscriber_acl := {
    "analytics_dashboard": {
        "cluster_connectivity.ClusterSessionOpened",
        "cluster_connectivity.ClusterSessionClosed",
        "cluster_connectivity.ClusterSessionDegraded",
        "cluster_connectivity.WatchStreamReconnected",
        "cluster_connectivity.WatchStreamDropped",
        "resource_browser.MutationApplied",
        "port_forwarding.PortForwardEstablished",
        "port_forwarding.PortForwardClosed",
        "helm_management.HelmRollbackInitiated",
        "helm_management.HelmManifestApplied",
        "helm_management.HelmRollbackCompleted",
    },
    "app_shell": {
        "cluster_connectivity.ClusterSessionOpened",
        "cluster_connectivity.ClusterSessionClosed",
        "cluster_connectivity.ClusterSessionDegraded",
        "resource_browser.MutationApplied",
        "resource_browser.DraftSaved",
    },
    "local_persistence": {
        "local_persistence.AuditEntryAppended",
        "resource_browser.MutationApplied",
    },
    "cluster_intelligence": {
        "cluster_connectivity.ClusterSessionOpened",
        "cluster_connectivity.ClusterSessionClosed",
        "resource_browser.MutationApplied",
    },
    "context_navigation": {
        "cluster_connectivity.ClusterSessionOpened",
        "cluster_connectivity.ClusterSessionClosed",
        "app_shell.ContextSwitched",
    },
    "assistant_chat": {
        "cluster_intelligence.ToolInvoked",
    },
    # The domain event bus meta-subscriber drains DomainEventDropped for
    # self-monitoring (ADR-0027). It may subscribe to any event type.
    "domain_event_bus": {
        "domain_event_bus.DomainEventDropped",
    },
}

# ---------------------------------------------------------------------------
# Rule: subscriber not permitted for this event type.
# Evaluated when input carries a subscriber field (subscribe-side evaluation).
# If input.subscriber is absent (publish-side check), this rule is a no-op.
# ---------------------------------------------------------------------------

deny contains msg if {
    input.subscriber != null
    input.subscriber != ""
    allowed := subscriber_acl[input.subscriber]
    not input.eventType in allowed
    msg := sprintf(
        "subscriber %q is not permitted to receive event type %q — update subscriber_acl in event_bus_policy.rego and ADR-0040 if this subscription is intentional",
        [input.subscriber, input.eventType],
    )
}

# ---------------------------------------------------------------------------
# Rule: unknown subscriber (not in ACL at all).
# ---------------------------------------------------------------------------

deny contains msg if {
    input.subscriber != null
    input.subscriber != ""
    not subscriber_acl[input.subscriber]
    msg := sprintf(
        "unknown subscriber %q — add an entry to subscriber_acl in event_bus_policy.rego and ADR-0040",
        [input.subscriber],
    )
}

# ---------------------------------------------------------------------------
# Payload credential scan.
# Serialised payload must not contain embedded API keys, tokens, or PEM
# material. Reuses patterns from local_persistence.secret_redaction.
# ---------------------------------------------------------------------------

# Known credential-shaped patterns (vendor-prefixed and format-anchored).
_secret_patterns := [
    # Anthropic
    `sk-(ant|proj|live|test)-[A-Za-z0-9_-]{16,}`,
    # OpenAI (legacy + project)
    `sk-[A-Za-z0-9]{20,}`,
    # Google AI
    `AIza[0-9A-Za-z_-]{35}`,
    # Hugging Face
    `hf_[A-Za-z0-9]{34,}`,
    # Azure OpenAI subscription key (32-hex GUID without hyphens)
    `[a-f0-9]{32}`,
    # PEM material markers
    `-----BEGIN (CERTIFICATE|PRIVATE KEY|RSA PRIVATE KEY|EC PRIVATE KEY)-----`,
]

payload_contains_secret(serialized) if {
    some pattern in _secret_patterns
    regex.match(pattern, serialized)
}

deny contains msg if {
    input.payloadSerialized != null
    input.payloadSerialized != ""
    payload_contains_secret(input.payloadSerialized)
    msg := sprintf(
        "event type %q: serialised payload contains a string matching a known credential pattern; credentials must not be published on the event bus",
        [input.eventType],
    )
}

# ---------------------------------------------------------------------------
# Tests (OPA test suite — run with: opa test event_bus_policy.rego)
# ---------------------------------------------------------------------------

# -- helper: minimal valid input for MutationApplied ------------------------

_valid_input := {
    "eventType": "resource_browser.MutationApplied",
    "envelope": {
        "eventId":       "01905e2a-dead-7000-beef-000000000001",
        "eventType":     "resource_browser.MutationApplied",
        "sourceContext": "resource_browser",
        "occurredAt":    "2026-05-15T10:00:00.000Z",
        "version":       1,
    },
    "payload": {
        "size": 512,
    },
}

# -- pass: valid envelope and known event type -------------------------------

test_allow_valid_event if {
    allow with input as _valid_input
}

# -- fail: unknown event type -----------------------------------------------

test_deny_unknown_event_type if {
    result := deny with input as object.union(
        _valid_input,
        {
            "eventType": "resource_browser.UnknownEvent",
            "envelope":  object.union(
                _valid_input.envelope,
                {"eventType": "resource_browser.UnknownEvent"},
            ),
        },
    )
    count(result) > 0
    some msg in result
    contains(msg, "unknown event type")
}

# -- fail: payload too large ------------------------------------------------

test_deny_oversized_payload if {
    result := deny with input as object.union(
        _valid_input,
        {"payload": {"size": 8192}},
    )
    count(result) > 0
    some msg in result
    contains(msg, "payload too large")
}

# -- fail: unsupported envelope version -------------------------------------

test_deny_bad_version if {
    result := deny with input as object.union(
        _valid_input,
        {"envelope": object.union(_valid_input.envelope, {"version": 2})},
    )
    count(result) > 0
    some msg in result
    contains(msg, "unsupported envelope version")
}

# -- fail: sourceContext does not match eventType prefix --------------------

test_deny_mismatched_source_context if {
    result := deny with input as object.union(
        _valid_input,
        {
            "eventType": "helm_management.HelmRollbackInitiated",
            "envelope":  object.union(
                _valid_input.envelope,
                {
                    "eventType":     "helm_management.HelmRollbackInitiated",
                    "sourceContext": "resource_browser",
                },
            ),
        },
    )
    count(result) > 0
    some msg in result
    contains(msg, "does not match sourceContext")
}

# -- fail: empty eventId ----------------------------------------------------

test_deny_empty_event_id if {
    result := deny with input as object.union(
        _valid_input,
        {"envelope": object.union(_valid_input.envelope, {"eventId": ""})},
    )
    count(result) > 0
    some msg in result
    contains(msg, "eventId must be a non-empty")
}

# -- fail: empty occurredAt -------------------------------------------------

test_deny_empty_occurred_at if {
    result := deny with input as object.union(
        _valid_input,
        {"envelope": object.union(_valid_input.envelope, {"occurredAt": ""})},
    )
    count(result) > 0
    some msg in result
    contains(msg, "occurredAt must be a non-empty")
}

# -- pass: DomainEventDropped meta-event (domain_event_bus source) ----------

test_allow_domain_event_dropped_meta_event if {
    allow with input as {
        "eventType": "domain_event_bus.DomainEventDropped",
        "envelope": {
            "eventId":       "01905e2a-dead-7000-beef-000000000002",
            "eventType":     "domain_event_bus.DomainEventDropped",
            "sourceContext": "domain_event_bus",
            "occurredAt":    "2026-05-15T10:00:01.000Z",
            "version":       1,
        },
        "payload": {
            "size": 128,
        },
    }
}

# -- pass: exactly 4096-byte payload is accepted (boundary) -----------------

test_allow_payload_at_exact_boundary if {
    allow with input as object.union(
        _valid_input,
        {"payload": {"size": 4096}},
    )
}

# -- fail: payload of 4097 bytes is rejected (one over boundary) ------------

test_deny_payload_one_over_boundary if {
    result := deny with input as object.union(
        _valid_input,
        {"payload": {"size": 4097}},
    )
    count(result) > 0
    some msg in result
    contains(msg, "payload too large")
}

# ---------------------------------------------------------------------------
# Subscriber ACL tests
# ---------------------------------------------------------------------------

# -- pass: analytics_dashboard may receive MutationApplied ------------------

test_allow_subscriber_analytics_mutation_applied if {
    allow with input as object.union(
        _valid_input,
        {
            "subscriber": "analytics_dashboard",
            "payloadSerialized": "",
        },
    )
}

# -- pass: app_shell may receive DraftSaved ----------------------------------

test_allow_subscriber_app_shell_draft_saved if {
    allow with input as {
        "eventType": "resource_browser.DraftSaved",
        "subscriber": "app_shell",
        "payloadSerialized": "",
        "envelope": {
            "eventId":       "01905e2a-dead-7000-beef-000000000010",
            "eventType":     "resource_browser.DraftSaved",
            "sourceContext": "resource_browser",
            "occurredAt":    "2026-05-15T10:00:00.000Z",
            "version":       1,
        },
        "payload": {"size": 64},
    }
}

# -- fail: app_shell may NOT receive HelmRollbackInitiated -------------------

test_deny_subscriber_app_shell_helm_event if {
    result := deny with input as {
        "eventType": "helm_management.HelmRollbackInitiated",
        "subscriber": "app_shell",
        "payloadSerialized": "",
        "envelope": {
            "eventId":       "01905e2a-dead-7000-beef-000000000011",
            "eventType":     "helm_management.HelmRollbackInitiated",
            "sourceContext": "helm_management",
            "occurredAt":    "2026-05-15T10:00:00.000Z",
            "version":       1,
        },
        "payload": {"size": 64},
    }
    count(result) > 0
    some msg in result
    contains(msg, "not permitted to receive")
}

# -- fail: unknown subscriber denied ----------------------------------------

test_deny_unknown_subscriber if {
    result := deny with input as object.union(
        _valid_input,
        {
            "subscriber":       "rogue_context",
            "payloadSerialized": "",
        },
    )
    count(result) > 0
    some msg in result
    contains(msg, "unknown subscriber")
}

# -- pass: absent subscriber field skips ACL check (publish-side) -----------

test_allow_absent_subscriber_skips_acl if {
    allow with input as object.union(
        _valid_input,
        {"payloadSerialized": ""},
    )
}

# ---------------------------------------------------------------------------
# Payload credential scan tests
# ---------------------------------------------------------------------------

# -- fail: Anthropic key in payload ----------------------------------------

test_deny_anthropic_key_in_payload if {
    result := deny with input as object.union(
        _valid_input,
        {
            "payloadSerialized": "sk-ant-api01-ABCDEFGHIJKLMNOPQRSTUVWXYZabcde",
            "subscriber":        "",
        },
    )
    count(result) > 0
    some msg in result
    contains(msg, "credential pattern")
}

# -- fail: Google AI key in payload ----------------------------------------

test_deny_google_ai_key_in_payload if {
    result := deny with input as object.union(
        _valid_input,
        {
            "payloadSerialized": "AIzaSyD-9tSrke72I6e0DVos2Vz8kAqnkPj9E0s",
            "subscriber":        "",
        },
    )
    count(result) > 0
    some msg in result
    contains(msg, "credential pattern")
}

# -- fail: Hugging Face token in payload ------------------------------------

test_deny_hf_token_in_payload if {
    result := deny with input as object.union(
        _valid_input,
        {
            "payloadSerialized": "hf_aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890ab",
            "subscriber":        "",
        },
    )
    count(result) > 0
}

# -- fail: PEM certificate fragment in payload ------------------------------

test_deny_pem_in_payload if {
    result := deny with input as object.union(
        _valid_input,
        {
            "payloadSerialized": "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBg==\n-----END PRIVATE KEY-----",
            "subscriber":        "",
        },
    )
    count(result) > 0
    some msg in result
    contains(msg, "credential pattern")
}

# -- pass: clean payload does not trigger credential scan -------------------

test_allow_clean_payload_no_credential_match if {
    allow with input as object.union(
        _valid_input,
        {
            "payloadSerialized": "{\"clusterId\":\"prod\",\"verb\":\"apply\",\"gvk\":\"apps/v1/Deployment\"}",
            "subscriber":        "",
        },
    )
}
