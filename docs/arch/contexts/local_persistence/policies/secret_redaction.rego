# DDD role: Policy
package local_persistence.secret_redaction

# DDD role: Policy
#
# These rules backstop the application's redaction logic — every
# string the persistence layer is about to write to SQLite is run
# against this policy. If a deny rule fires, the write is rejected
# with a developer-facing error (the situation indicates a bug in
# upstream sanitisation).
#
# Credential-detection strategy (two independent signals — either fires):
#   1. Pattern match: value matches a known vendor-specific regex.
#   2. Label match: field name matches a sensitive-field regex AND value
#      is long enough to be a credential. The kind=="secret_candidate"
#      hint remains one signal among several, not the sole gate.

# Strings that look like LLM API keys are never persisted in SQLite.
# Keychain entries are managed elsewhere.
deny[msg] {
    some i
    field := input.fields[i]
    matches_api_key(field.value)
    msg := sprintf("field %q contains a string matching an LLM API key pattern", [field.name])
}

# Strings that look like Kubernetes bearer tokens or client
# certificates are not persisted in SQLite.
deny[msg] {
    some i
    field := input.fields[i]
    matches_bearer_token(field.value)
    msg := sprintf("field %q contains a string matching a Kubernetes bearer token", [field.name])
}

deny[msg] {
    some i
    field := input.fields[i]
    contains_pem_certificate(field.value)
    msg := sprintf("field %q contains an embedded PEM certificate", [field.name])
}

# Label-based catch-all: fields whose name indicates a credential
# (token, api_key, secret, password, credential, bearer) AND whose
# value is a plausible credential (≥32 URL-safe chars) are denied
# regardless of the kind hint. The kind=="secret_candidate" hint
# from the upstream serialiser is one supported signal but must not
# be the sole gate.
deny[msg] {
    some i
    field := input.fields[i]
    sensitive_field_label(field.name)
    regex.match(`^[A-Za-z0-9_-]{32,}$`, field.value)
    msg := sprintf("field %q has a sensitive name and contains a long credential-shaped value; use Keychain storage instead", [field.name])
}

# ---------- Pattern helpers — vendor-specific API keys ----------

# Anthropic (sk-ant-*, sk-proj-*, sk-live-*, sk-test-*)
matches_api_key(value) {
    regex.match(`^sk-(ant|proj|live|test)-[A-Za-z0-9_-]{16,}$`, value)
}

# OpenAI (sk-... legacy and sk-proj-... project keys)
matches_api_key(value) {
    regex.match(`^sk-[A-Za-z0-9]{20,}$`, value)
}

# Google AI (Gemini / PaLM): AIza followed by 35 alphanumeric/dash/underscore chars
matches_api_key(value) {
    regex.match(`^AIza[0-9A-Za-z_-]{35}$`, value)
}

# Hugging Face tokens: hf_ followed by ≥34 alphanumeric chars
matches_api_key(value) {
    regex.match(`^hf_[A-Za-z0-9]{34,}$`, value)
}

# Azure OpenAI subscription keys: exactly 32 lowercase hex chars (GUID without hyphens)
matches_api_key(value) {
    regex.match(`^[a-f0-9]{32}$`, value)
}

# Generic secret_candidate signal: long URL-safe string with the upstream kind hint.
# The kind hint alone is no longer sufficient (must be accompanied by one of the
# specific patterns above or the label-based catch-all below), but we retain this
# rule to preserve backward compatibility with callers that set kind=="secret_candidate".
matches_api_key(value) {
    regex.match(`^[A-Za-z0-9_-]{32,}$`, value)
    some i
    field := input.fields[i]
    field.value == value
    field.kind == "secret_candidate"
}

# ---------- Pattern helpers — label-based sensitive field detection ----------

# Field name matches common credential-bearing column names, case-insensitively.
sensitive_field_label(name) {
    regex.match(`(?i)(token|api[_-]?key|secret|password|credential|bearer)`, name)
}

# ---------- Pattern helpers — bearer tokens and certificates ----------

matches_bearer_token(value) {
    # Kubernetes serviceaccount tokens are typically dot-separated JWTs.
    regex.match(`^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$`, value)
}

contains_pem_certificate(value) {
    contains(value, "-----BEGIN CERTIFICATE-----")
}

contains_pem_certificate(value) {
    contains(value, "-----BEGIN PRIVATE KEY-----")
}

contains_pem_certificate(value) {
    contains(value, "-----BEGIN RSA PRIVATE KEY-----")
}

contains_pem_certificate(value) {
    contains(value, "-----BEGIN EC PRIVATE KEY-----")
}
