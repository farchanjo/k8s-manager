# DDD role: PolicyTest
package local_persistence.secret_redaction

import future.keywords.in

# secret_redaction_test.rego
#
# Unit tests for the new patterns added in the 2026-05-15 audit fix:
#   - Google AI (AIza...)
#   - Hugging Face (hf_...)
#   - Azure OpenAI (32-hex GUID)
#   - Label-based catch-all (sensitive field name + long value, no kind hint)

# ---------------------------------------------------------------------------
# Helpers: build a single-field input
# ---------------------------------------------------------------------------

_field(name, value) = {"fields": [{"name": name, "value": value, "kind": "normal"}]}

_field_with_kind(name, value, kind) = {"fields": [{"name": name, "value": value, "kind": kind}]}

# ---------------------------------------------------------------------------
# Google AI (AIza + 35 chars)
# ---------------------------------------------------------------------------

test_deny_google_ai_key {
    result := deny with input as _field(
        "google_key",
        "AIzaSyD-9tSrke72I6e0DVos2Vz8kAqnkPj9E0s"
    )
    count(result) > 0
    some msg in result
    contains(msg, "LLM API key pattern")
}

test_allow_google_prefix_but_too_short {
    # AIza + 34 chars (one short) — must not match
    result := deny with input as _field(
        "google_key",
        "AIzaSyD-9tSrke72I6e0DVos2Vz8kAqnkPj9E0"
    )
    # No deny from matches_api_key; might fire from label catch-all if name is sensitive
    # Since name is "google_key" (no token/secret/password/api_key), no deny expected
    count(result) == 0
}

# ---------------------------------------------------------------------------
# Hugging Face (hf_ + ≥34 chars)
# ---------------------------------------------------------------------------

test_deny_hugging_face_token {
    result := deny with input as _field(
        "hf_token",
        "hf_aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890ab"
    )
    count(result) > 0
}

test_deny_hugging_face_token_exact_34 {
    result := deny with input as _field(
        "hf_api_key",
        "hf_aBcDeFgHiJkLmNoPqRsTuVwXyZ12345678"
    )
    count(result) > 0
}

test_allow_hf_prefix_too_short {
    # hf_ + 33 chars → does not reach 34 minimum
    result := deny with input as _field(
        "some_field",
        "hf_aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567"
    )
    count(result) == 0
}

# ---------------------------------------------------------------------------
# Azure OpenAI (32 lowercase hex)
# ---------------------------------------------------------------------------

test_deny_azure_openai_key {
    result := deny with input as _field(
        "azure_key",
        "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
    )
    count(result) > 0
}

test_deny_azure_openai_key_all_zeros {
    result := deny with input as _field(
        "azure_subscription_key",
        "00000000000000000000000000000000"
    )
    count(result) > 0
}

test_allow_azure_key_with_uppercase {
    # Must NOT match (pattern requires lowercase hex only)
    result := deny with input as _field(
        "some_field",
        "A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4"
    )
    # No vendor match; no sensitive label name
    count(result) == 0
}

test_allow_azure_key_31_chars {
    # One char short of 32 — must not match
    result := deny with input as _field(
        "some_field",
        "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d"
    )
    count(result) == 0
}

# ---------------------------------------------------------------------------
# Label-based catch-all — sensitive field name + long value (no kind hint)
# ---------------------------------------------------------------------------

test_deny_label_api_key_long_value_no_kind_hint {
    result := deny with input as _field(
        "api_key",
        "someLongCredentialValueThatIsThirtyTwoCharsLong"
    )
    count(result) > 0
    some msg in result
    contains(msg, "sensitive name")
}

test_deny_label_token_long_value {
    result := deny with input as _field(
        "access_token",
        "abcdefghijklmnopqrstuvwxyz123456789012"
    )
    count(result) > 0
}

test_deny_label_password_long_value {
    result := deny with input as _field(
        "db_password",
        "SuperSecretPasswordValueThatIsTooLong"
    )
    count(result) > 0
}

test_deny_label_bearer_long_value {
    result := deny with input as _field(
        "bearer_credential",
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ"
    )
    count(result) > 0
}

test_deny_label_secret_long_value {
    result := deny with input as _field(
        "client_secret",
        "xyzzy1234567890abcdefghijklmnopqrstuv"
    )
    count(result) > 0
}

test_allow_sensitive_label_but_short_value {
    # Value is only 10 chars — too short to be a credential
    result := deny with input as _field(
        "api_key",
        "short-val"
    )
    count(result) == 0
}

test_allow_non_sensitive_label_with_long_value_no_kind {
    # Label "cluster_name" is not credential-bearing; no kind hint → must not deny
    result := deny with input as _field(
        "cluster_name",
        "abcdefghijklmnopqrstuvwxyz123456789012"
    )
    count(result) == 0
}

# ---------------------------------------------------------------------------
# kind=="secret_candidate" still fires (backward-compat)
# ---------------------------------------------------------------------------

test_deny_kind_secret_candidate_still_works {
    result := deny with input as _field_with_kind(
        "some_field",
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN",
        "secret_candidate"
    )
    count(result) > 0
}

# ---------------------------------------------------------------------------
# Existing Anthropic / OpenAI patterns still work
# ---------------------------------------------------------------------------

test_deny_anthropic_key {
    result := deny with input as _field(
        "anthropic_key",
        "sk-ant-api01-ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-xyz"
    )
    count(result) > 0
}

test_deny_pem_certificate {
    result := deny with input as _field(
        "cert",
        "-----BEGIN CERTIFICATE-----\nMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA\n-----END CERTIFICATE-----"
    )
    count(result) > 0
    some msg in result
    contains(msg, "PEM certificate")
}

test_deny_jwt_bearer_token {
    result := deny with input as _field(
        "sa_token",
        "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJzeXN0ZW06c2VydmljZWFjY291bnQ6ZGVmYXVsdDpkZWZhdWx0In0.SIGNATURE"
    )
    count(result) > 0
    some msg in result
    contains(msg, "bearer token")
}
