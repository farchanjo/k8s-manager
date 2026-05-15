# DDD role: Policy
package llm_provider.provider_policy

# provider_policy.rego
#
# Governs LLM provider configuration. Enforces that API keys originate
# from the macOS Keychain, that provider endpoints use HTTPS only, and
# that private-network addresses are accepted only when explicitly
# marked as local-only (e.g. Ollama, LM Studio).
#
# input.apiKeySource      — "keychain" | "inline" | "env"
# input.endpointURL       — string: the full provider base URL
# input.localOnly         — bool: operator explicitly flagged this as a
#                           local-only provider (Ollama / LM Studio)
# input.providerName      — string: display name of the provider profile

default allow := false

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

is_https(url) {
    startswith(url, "https://")
}

is_localhost(url) {
    startswith(url, "https://localhost")
}

is_loopback_ip(url) {
    startswith(url, "https://127.")
}

is_private_192(url) {
    startswith(url, "https://192.168.")
}

is_private_10(url) {
    startswith(url, "https://10.")
}

is_private_172(url) {
    startswith(url, "https://172.16.")
}

is_private_172_17(url) {
    startswith(url, "https://172.17.")
}

is_private_172_31(url) {
    startswith(url, "https://172.31.")
}

is_private_network(url) {
    is_localhost(url)
}

is_private_network(url) {
    is_loopback_ip(url)
}

is_private_network(url) {
    is_private_192(url)
}

is_private_network(url) {
    is_private_10(url)
}

is_private_network(url) {
    is_private_172(url)
}

is_private_network(url) {
    is_private_172_17(url)
}

is_private_network(url) {
    is_private_172_31(url)
}

# ---------------------------------------------------------------------------
# Happy-path allow rules
# ---------------------------------------------------------------------------

# Public HTTPS endpoint with Keychain-sourced API key.
allow {
    input.apiKeySource == "keychain"
    is_https(input.endpointURL)
    not is_private_network(input.endpointURL)
}

# Local-only provider (Ollama, LM Studio) with explicit localOnly flag.
# API key requirement is relaxed for local providers (they may use no key).
allow {
    input.localOnly == true
    is_https(input.endpointURL)
    is_private_network(input.endpointURL)
}

# ---------------------------------------------------------------------------
# Deny rules
# ---------------------------------------------------------------------------

deny_inline_api_key[msg] {
    input.apiKeySource != "keychain"
    msg := sprintf(
        "provider %q: API key must be stored in the macOS Keychain (source=%q); inline or environment-variable keys are not permitted",
        [input.providerName, input.apiKeySource]
    )
}

deny_non_https_endpoint[msg] {
    not is_https(input.endpointURL)
    msg := sprintf(
        "provider %q: endpoint URL %q must use HTTPS; plaintext HTTP is not permitted",
        [input.providerName, input.endpointURL]
    )
}

deny_private_network_without_local_only[msg] {
    is_https(input.endpointURL)
    is_private_network(input.endpointURL)
    input.localOnly == false
    msg := sprintf(
        "provider %q: endpoint %q resolves to a private-network address; set localOnly=true to permit local providers such as Ollama or LM Studio",
        [input.providerName, input.endpointURL]
    )
}

# ---------------------------------------------------------------------------
# Negative test cases
#
# test_deny_inline_key:
#   input = {
#     "apiKeySource": "inline",
#     "endpointURL": "https://api.openai.com",
#     "localOnly": false,
#     "providerName": "OpenAI"
#   }
#   expect: allow == false
#   expect: deny_inline_api_key contains "must be stored in the macOS Keychain"
#
# test_deny_http_endpoint:
#   input = {
#     "apiKeySource": "keychain",
#     "endpointURL": "http://api.openai.com",
#     "localOnly": false,
#     "providerName": "OpenAI"
#   }
#   expect: allow == false
#   expect: deny_non_https_endpoint contains "must use HTTPS"
#
# test_deny_private_network_not_local_only:
#   input = {
#     "apiKeySource": "keychain",
#     "endpointURL": "https://192.168.1.100:11434",
#     "localOnly": false,
#     "providerName": "Local LLM"
#   }
#   expect: allow == false
#   expect: deny_private_network_without_local_only contains "private-network address"
# ---------------------------------------------------------------------------
