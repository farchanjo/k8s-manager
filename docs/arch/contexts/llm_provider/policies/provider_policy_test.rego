# DDD role: PolicyTest
package llm_provider.provider_policy

import future.keywords.in

# provider_policy_test.rego
#
# Unit tests covering all new branches added in the 2026-05-15 audit fix:
#   - IPv6 loopback (::1)
#   - IPv4 link-local 169.254.x.x
#   - IPv6 link-local fe80::
#   - IPv6 unique-local fc00::/7
#   - 0.0.0.0 unspecified address
#   - *.local, *.internal, *.lan mDNS hostnames
#   - Full RFC 1918 172.16.0.0/12 (not just 172.16, 172.17, 172.31)
#   - http://localhost exception with localOnly=true (Ollama use case)

# ---------------------------------------------------------------------------
# Shared base inputs
# ---------------------------------------------------------------------------

_keychain_openai := {
    "apiKeySource": "keychain",
    "endpointURL": "https://api.openai.com",
    "localOnly": false,
    "providerName": "OpenAI",
}

_local_ollama_https := {
    "apiKeySource": "keychain",
    "endpointURL": "https://localhost:11434",
    "localOnly": true,
    "providerName": "Ollama-HTTPS",
}

_local_ollama_http := {
    "apiKeySource": "keychain",
    "endpointURL": "http://localhost:11434",
    "localOnly": true,
    "providerName": "Ollama",
}

# ---------------------------------------------------------------------------
# Existing happy paths still pass
# ---------------------------------------------------------------------------

test_allow_public_https_keychain {
    allow with input as _keychain_openai
}

test_allow_local_only_https_loopback {
    allow with input as _local_ollama_https
}

# ---------------------------------------------------------------------------
# http://localhost with localOnly=true — Ollama use case (ADR-0045)
# ---------------------------------------------------------------------------

test_allow_http_localhost_local_only {
    allow with input as _local_ollama_http
}

test_deny_non_https_does_not_fire_for_http_localhost_local_only {
    result := deny_non_https_endpoint with input as _local_ollama_http
    count(result) == 0
}

test_deny_http_localhost_when_not_local_only {
    not allow with input as object.union(
        _local_ollama_http,
        {"localOnly": false}
    )
}

test_deny_http_non_localhost_always_denied {
    not allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "http://api.openai.com",
        "localOnly": false,
        "providerName": "OpenAI",
    }
}

# ---------------------------------------------------------------------------
# IPv6 loopback ::1
# ---------------------------------------------------------------------------

test_allow_ipv6_loopback_local_only_https {
    allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://[::1]:11434",
        "localOnly": true,
        "providerName": "Ollama-IPv6",
    }
}

test_deny_ipv6_loopback_not_local_only {
    not allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://[::1]:11434",
        "localOnly": false,
        "providerName": "Ollama-IPv6",
    }
}

# ---------------------------------------------------------------------------
# IPv4 link-local 169.254.0.0/16
# ---------------------------------------------------------------------------

test_deny_link_local_ipv4 {
    not allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://169.254.1.1:11434",
        "localOnly": false,
        "providerName": "BadProvider",
    }
}

test_deny_link_local_ipv4_fires_msg {
    result := deny_link_local_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://169.254.169.254",
        "localOnly": false,
        "providerName": "IMDS",
    }
    count(result) > 0
    some msg in result
    contains(msg, "link-local")
}

test_deny_link_local_ipv4_even_with_local_only {
    # link-local is never permitted, regardless of localOnly
    result := deny_link_local_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://169.254.0.1",
        "localOnly": true,
        "providerName": "BadLocal",
    }
    count(result) > 0
}

# ---------------------------------------------------------------------------
# IPv6 link-local fe80::/10
# ---------------------------------------------------------------------------

test_deny_ipv6_link_local {
    result := deny_link_local_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://[fe80::1%25eth0]:11434",
        "localOnly": false,
        "providerName": "BadIPv6",
    }
    count(result) > 0
    some msg in result
    contains(msg, "link-local")
}

# ---------------------------------------------------------------------------
# IPv6 unique-local fc00::/7 (fc:: and fd:: prefixes)
# ---------------------------------------------------------------------------

test_deny_ipv6_unique_local_fc {
    result := deny_ipv6_unique_local_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://[fc00::1]:11434",
        "localOnly": false,
        "providerName": "BadIPv6",
    }
    count(result) > 0
    some msg in result
    contains(msg, "fc00::/7")
}

test_deny_ipv6_unique_local_fd {
    result := deny_ipv6_unique_local_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://[fd12:3456::1]:11434",
        "localOnly": false,
        "providerName": "DockerIPv6",
    }
    count(result) > 0
}

# ---------------------------------------------------------------------------
# 0.0.0.0 unspecified address
# ---------------------------------------------------------------------------

test_deny_unspecified_address {
    not allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://0.0.0.0:11434",
        "localOnly": false,
        "providerName": "BadBind",
    }
}

test_deny_unspecified_fires_msg {
    result := deny_unspecified_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://0.0.0.0",
        "localOnly": false,
        "providerName": "BadBind",
    }
    count(result) > 0
    some msg in result
    contains(msg, "unspecified address")
}

# ---------------------------------------------------------------------------
# mDNS / zero-config hostnames: *.local, *.internal, *.lan
# ---------------------------------------------------------------------------

test_deny_dot_local_hostname {
    result := deny_mdns_hostname_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://ollama.local:11434",
        "localOnly": true,
        "providerName": "mDNS",
    }
    count(result) > 0
    some msg in result
    contains(msg, ".local")
}

test_deny_dot_internal_hostname {
    result := deny_mdns_hostname_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://llm.internal:11434",
        "localOnly": false,
        "providerName": "Internal",
    }
    count(result) > 0
}

test_deny_dot_lan_hostname {
    result := deny_mdns_hostname_endpoint with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://gpu-server.lan:8080",
        "localOnly": false,
        "providerName": "LAN",
    }
    count(result) > 0
}

# ---------------------------------------------------------------------------
# RFC 1918 172.16.0.0/12 — full range (fix for partial enumeration)
# ---------------------------------------------------------------------------

test_deny_172_16_private {
    not allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://172.16.0.1:11434",
        "localOnly": false,
        "providerName": "Docker",
    }
}

test_deny_172_18_was_previously_missed {
    # 172.18.x.x was NOT covered by old policy (only 172.16, 172.17, 172.31)
    not allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://172.18.0.1:11434",
        "localOnly": false,
        "providerName": "DockerBridge",
    }
}

test_deny_172_20_private {
    not allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://172.20.0.1",
        "localOnly": false,
        "providerName": "VPN",
    }
}

test_deny_172_31_private {
    not allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://172.31.255.254",
        "localOnly": false,
        "providerName": "AWSSubnet",
    }
}

test_allow_172_32_is_public {
    # 172.32.x.x is outside 172.16.0.0/12 and should NOT be treated as private
    allow with input as {
        "apiKeySource": "keychain",
        "endpointURL": "https://172.32.0.1",
        "localOnly": false,
        "providerName": "PublicIP",
    }
}
