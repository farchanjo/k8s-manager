# ADR-0045 — LLM provider local-only endpoint policy

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — llm-provider, security, policy, network, llm_provider

## Context and problem statement

ADR-0008 introduces the LLM provider abstraction with support for Anthropic, OpenAI, and any
OpenAI-compatible endpoint (Ollama, LM Studio, vLLM, OpenRouter). The OpenAI-compatible category
includes both private localhost services (Ollama on `127.0.0.1:11434`) and public hosted services.
Operators routinely register both. A configuration that accidentally points a "remote" provider
entry at `localhost` or, conversely, marks a remote endpoint as "local-only" can leak provider keys
or chat content to unintended destinations. The Gherkin scenarios
`docs/arch/contexts/llm_provider/features/lifecycle/localhost-allowed-for-ollama.feature` and
`docs/arch/contexts/llm_provider/features/lifecycle/localhost-denied-without-flag.feature` exercise
this boundary but no ADR defines the policy.

## Decision drivers

- **Prevent silent data leak** — a misconfigured profile that points a "public" provider at a
  non-routable address must fail loudly, not silently.
- **Support legitimate localhost models** — Ollama, LM Studio, vLLM, and llama.cpp all bind to
  loopback by default.
- **No surprises across operator devices** — the same profile must behave identically on every
  machine; localhost on machine A is not localhost on machine B.
- **Network policy is policy** — enforcement at the Rego layer keeps the rule explicit and testable.

## Considered options

1. **No localhost handling** — rejected. Operators cannot use local models or local models are
   reachable without flag.
2. **Implicit localhost detection** — rejected. Allowing any 127/8 address by default lets
   remote-typed profiles silently work locally; remote misconfiguration is invisible.
3. **Explicit `localOnly: true` flag with policy enforcement** — chosen.
4. **Per-profile network allowlist** — rejected for MVP++. Adds schema complexity without a concrete
   use case beyond local vs remote.

## Pros and cons of the options

### Option 1 — No localhost handling

- Bad, because operators cannot safely use local models (Ollama, LM Studio) without either
  permanently allowing all addresses or having no guarantee about where their chat content is sent.

### Option 2 — Implicit localhost detection

- Bad, because allowing any `127/8` address by default lets remote-typed profiles silently work
  locally; a remote misconfiguration that routes to localhost is invisible to both the operator and
  the audit log.

### Option 3 — Explicit `localOnly: true` flag with policy enforcement (chosen)

- Good, because explicit intent at profile-creation time prevents silent misconfiguration in both
  directions: a public profile cannot silently resolve to localhost, and a local-only profile cannot
  accidentally target a public endpoint.
- Good, because the Rego policy at both profile-save and per-request validation is auditable and
  every violation writes a `ProviderEndpointPolicyViolation` audit entry.
- Bad, because operators behind transparent proxies may need to temporarily disable the policy; no
  escape hatch is provided in MVP++.

### Option 4 — Per-profile network allowlist

- Bad, because it adds schema complexity (allowlist entries per profile, CIDR validation, merge
  semantics) without a concrete use case beyond the local-vs-remote distinction already covered by
  the `localOnly` flag.

## Decision outcome

- **Schema**: every `#ProviderProfile` carries a `localOnly: bool` field (default `false`).
- **Endpoint URL constraint**:
  - When `localOnly == false`: the endpoint URL MUST resolve to a non-private address. Private
    ranges blocked: `127.0.0.0/8`, `0.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
    `169.254.0.0/16` (link-local), `fc00::/7` (ULA), `fe80::/10` (link-local IPv6), `::1/128`
    (loopback IPv6). Hostnames `localhost`, `*.local`, `*.internal`, `*.lan` are blocked at the
    policy layer regardless of resolution.
  - When `localOnly == true`: the endpoint URL MUST resolve to a private address from the list
    above. Public addresses are rejected. This prevents a "local-only" profile from accidentally
    targeting a public endpoint.
- **Scheme constraint**: when `localOnly == false`, only `https://` is permitted. When
  `localOnly == true`, both `http://` and `https://` are permitted (local models commonly use
  plaintext on loopback).
- **Policy file**: `docs/arch/contexts/llm_provider/policies/provider_policy.rego` enforces both
  directions. Profile-save and per-request validation both consult the policy.
- **Audit entry**: any rejection writes a `ProviderEndpointPolicyViolation` audit entry with the
  violation reason; the request is not issued.
- **Profile creation UX**: the settings UI exposes the `localOnly` toggle prominently when the
  operator types a localhost URL, prompting them to confirm intent.

### Consequences

- **Positive** — explicit intent at profile-creation time prevents silent leaks; both directions of
  misconfiguration are caught; policy is auditable.
- **Negative** — operators behind transparent proxies (rare but exists in enterprise) may need to
  disable the policy temporarily; no escape hatch yet — out-of-scope for MVP++.
- **Neutral** — the policy applies regardless of the underlying provider (Anthropic, OpenAI,
  custom); `localOnly` flag is orthogonal to the provider kind.

### Confirmation

- Schema test: `#ProviderProfile.localOnly == false` + endpoint `127.0.0.1:11434` → policy denies
  with `endpoint_must_be_public`.
- Schema test: `#ProviderProfile.localOnly == true` + endpoint `api.anthropic.com` → policy denies
  with `endpoint_must_be_local`.
- Schema test: `#ProviderProfile.localOnly == false` + endpoint `http://api.openai.com` → policy
  denies with `scheme_must_be_https`.
- Schema test: `#ProviderProfile.localOnly == true` + endpoint `http://localhost:11434` → policy
  allows.
- Audit log: every denial writes exactly one `ProviderEndpointPolicyViolation` entry.

## More information

- ADR-0008 — LLM provider abstraction.
- ADR-0010 — Local persistence (provider profile storage; API key in Keychain).
- ADR-0018 — Native cloud credential resolution (network policy patterns for cluster credentials).
- ADR-0027 — App self-monitoring (audit surface).
- Rego policy: `docs/arch/contexts/llm_provider/policies/provider_policy.rego`.
- Gherkin scenarios:
  `docs/arch/contexts/llm_provider/features/lifecycle/localhost-allowed-for-ollama.feature`,
  `docs/arch/contexts/llm_provider/features/lifecycle/localhost-denied-without-flag.feature`.
