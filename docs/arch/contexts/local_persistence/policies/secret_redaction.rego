# DDD role: Policy
package local_persistence.secret_redaction

# DDD role: Policy
#
# These rules backstop the application's redaction logic — every
# string the persistence layer is about to write to SQLite is run
# against this policy. If a deny rule fires, the write is rejected
# with a developer-facing error (the situation indicates a bug in
# upstream sanitisation).

# Strings that look like LLM API keys are never persisted in
# SQLite. Keychain entries are managed elsewhere.
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

# ---------- Pattern helpers ----------

matches_api_key(value) {
    regex.match(`^sk-(ant|proj|live|test)-[A-Za-z0-9_-]{16,}$`, value)
}

matches_api_key(value) {
    regex.match(`^[A-Za-z0-9_-]{32,}$`, value)
    # require either an "anthropic"/"openai" hint to reduce false
    # positives on benign long strings; the upstream serialiser
    # supplies hints in input.fields[i].kind.
    some i
    field := input.fields[i]
    field.value == value
    field.kind == "secret_candidate"
}

matches_bearer_token(value) {
    # Kubernetes serviceaccount tokens are typically dot-separated
    # JWTs.
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
