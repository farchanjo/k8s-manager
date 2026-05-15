# DDD role: Policy
package llm_provider.provider_policy

# provider_policy.rego
#
# Governs LLM provider configuration. Enforces that API keys originate
# from the macOS Keychain, that provider endpoints use HTTPS only, and
# that private-network addresses are accepted only when explicitly
# marked as local-only (e.g. Ollama, LM Studio).
#
# ADR-0045 "Endpoint URL constraint" is the normative source for all
# address-space restrictions in this policy.
#
# input.apiKeySource      — "keychain" | "inline" | "env"
# input.endpointURL       — string: the full provider base URL
# input.localOnly         — bool: operator explicitly flagged this as a
#                           local-only provider (Ollama / LM Studio)
# input.providerName      — string: display name of the provider profile

default allow := false

# ---------------------------------------------------------------------------
# Helpers — scheme checks
# ---------------------------------------------------------------------------

is_https(url) {
    startswith(url, "https://")
}

# http:// loopback is permitted only when localOnly=true (Ollama use case,
# ADR-0045 + localhost-allowed-for-ollama.feature). All other HTTP is denied.
is_http_localhost(url) {
    startswith(url, "http://localhost")
}

# ---------------------------------------------------------------------------
# Helpers — loopback / private address detection
# ---------------------------------------------------------------------------

# IPv4 loopback
is_loopback(url) {
    startswith(url, "https://localhost")
}

is_loopback(url) {
    startswith(url, "https://127.")
}

is_loopback(url) {
    startswith(url, "http://localhost")
}

# IPv6 loopback (::1) — covers both bare and bracketed forms
is_loopback(url) {
    startswith(url, "https://[::1]")
}

is_loopback(url) {
    startswith(url, "http://[::1]")
}

# RFC 1918 private ranges
is_private_192(url) {
    startswith(url, "https://192.168.")
}

is_private_10(url) {
    startswith(url, "https://10.")
}

# Full RFC 1918 172.16.0.0/12 range (172.16.x.x – 172.31.x.x).
# Previous policy only enumerated 172.16, 172.17, and 172.31 leaving
# 172.18–172.30 unprotected. This helper is replaced by the CIDR check
# in is_private_172_cidr below; the old per-prefix helpers are removed.
is_private_172_cidr(url) {
    # Extract the host from the URL by stripping the scheme prefix.
    # startswith guards ensure we only process https:// URLs here.
    startswith(url, "https://172.")
    # Parse the dotted-decimal host portion (second octet must be 16–31).
    # OPA does not have a built-in CIDR match for string URLs; we extract
    # the host segment and feed it to net.cidr_contains.
    rest := substring(url, count("https://"), -1)
    # rest starts with "172.X..." — find the first non-digit, non-dot char
    # (port colon or path slash) to isolate the host.
    host := regex.find_n(`^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+`, rest, 1)[0]
    net.cidr_contains("172.16.0.0/12", host)
}

is_private_network(url) {
    is_loopback(url)
}

is_private_network(url) {
    is_private_192(url)
}

is_private_network(url) {
    is_private_10(url)
}

is_private_network(url) {
    is_private_172_cidr(url)
}

# ---------------------------------------------------------------------------
# Helpers — link-local and special addresses (ADR-0045)
# ---------------------------------------------------------------------------

# IPv4 link-local: 169.254.0.0/16
is_link_local(url) {
    startswith(url, "https://169.254.")
}

is_link_local(url) {
    startswith(url, "http://169.254.")
}

# IPv6 link-local: fe80::/10 (bracketed form used in URLs per RFC 2732)
is_link_local(url) {
    startswith(url, "https://[fe80")
}

is_link_local(url) {
    startswith(url, "http://[fe80")
}

# IPv6 unique-local: fc00::/7 (fc00:: and fd00:: prefixes, bracketed)
is_ipv6_unique_local(url) {
    startswith(url, "https://[fc")
}

is_ipv6_unique_local(url) {
    startswith(url, "https://[fd")
}

is_ipv6_unique_local(url) {
    startswith(url, "http://[fc")
}

is_ipv6_unique_local(url) {
    startswith(url, "http://[fd")
}

# The unspecified address 0.0.0.0
is_unspecified(url) {
    startswith(url, "https://0.0.0.0")
}

is_unspecified(url) {
    startswith(url, "http://0.0.0.0")
}

# mDNS / zero-config hostnames: *.local, *.internal, *.lan
is_mdns_hostname(url) {
    # Strip scheme then check hostname suffix before any port or path.
    rest := regex.find_n(`(?i)^[a-z]+://([a-zA-Z0-9._-]+)`, url, 1)[0]
    host := regex.find_n(`(?i)//([a-zA-Z0-9._-]+)`, rest, 1)[0]
    regex.match(`(?i)//[a-zA-Z0-9._-]+\.(local|internal|lan)(:|/|$)`, url)
}

# ---------------------------------------------------------------------------
# Happy-path allow rules
# ---------------------------------------------------------------------------

# Public HTTPS endpoint with Keychain-sourced API key.
allow {
    input.apiKeySource == "keychain"
    is_https(input.endpointURL)
    not is_private_network(input.endpointURL)
    not is_link_local(input.endpointURL)
    not is_ipv6_unique_local(input.endpointURL)
    not is_unspecified(input.endpointURL)
    not is_mdns_hostname(input.endpointURL)
}

# Local-only provider with HTTPS (Ollama / LM Studio — private IP or loopback).
allow {
    input.localOnly == true
    is_https(input.endpointURL)
    is_private_network(input.endpointURL)
}

# Local-only provider with plain HTTP to localhost only (Ollama default port
# 11434 uses HTTP, not HTTPS — ADR-0045 + localhost-allowed-for-ollama.feature).
allow {
    input.localOnly == true
    is_http_localhost(input.endpointURL)
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

# is_ollama_http_exception is true when http://localhost is permitted.
# Used to suppress deny_non_https_endpoint for the Ollama local use case.
is_ollama_http_exception {
    input.localOnly == true
    startswith(input.endpointURL, "http://localhost")
}

# HTTP is denied except for http://localhost when localOnly=true.
deny_non_https_endpoint[msg] {
    not is_https(input.endpointURL)
    not is_ollama_http_exception
    msg := sprintf(
        "provider %q: endpoint URL %q must use HTTPS; plaintext HTTP is not permitted (exception: http://localhost with localOnly=true for Ollama)",
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

# Deny link-local addresses unconditionally (169.254.x.x, fe80::).
deny_link_local_endpoint[msg] {
    is_link_local(input.endpointURL)
    msg := sprintf(
        "provider %q: endpoint %q is a link-local address (169.254.0.0/16 or fe80::/10) and is never permitted",
        [input.providerName, input.endpointURL]
    )
}

# Deny IPv6 unique-local addresses (fc00::/7) unconditionally.
deny_ipv6_unique_local_endpoint[msg] {
    is_ipv6_unique_local(input.endpointURL)
    msg := sprintf(
        "provider %q: endpoint %q is an IPv6 unique-local address (fc00::/7) and is never permitted",
        [input.providerName, input.endpointURL]
    )
}

# Deny 0.0.0.0 — unspecified address.
deny_unspecified_endpoint[msg] {
    is_unspecified(input.endpointURL)
    msg := sprintf(
        "provider %q: endpoint %q uses the unspecified address 0.0.0.0, which is never permitted",
        [input.providerName, input.endpointURL]
    )
}

# Deny mDNS / zero-config hostnames: *.local, *.internal, *.lan.
deny_mdns_hostname_endpoint[msg] {
    is_mdns_hostname(input.endpointURL)
    msg := sprintf(
        "provider %q: endpoint %q uses a mDNS/zero-config hostname (.local, .internal, or .lan); these are not permitted as LLM provider endpoints",
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
