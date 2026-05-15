# ADR-0044 — PromQL injection prevention policy

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — metrics, promql, injection, policy, metrics_observability, security

## Context and problem statement

ADR-0016 introduces curated PromQL templates with `{namespace}`, `{podName}`, `{containerName}`, and
similar placeholder substitutions sourced from Kubernetes resource names. Kubernetes label values
are permitted to contain a wider character set than is safe to interpolate into a PromQL expression.
A namespace name like `prod}|drop_metric{` or a pod annotation containing `__name__=~".+"` allows
the operator to escape the intended label selector and either bypass intended filters or trigger
expensive recursive queries. The Gherkin scenario
`docs/arch/contexts/metrics_observability/features/lifecycle/query-injection-blocked.feature`
exercises this case but no ADR defines the policy or the regex.

## Decision drivers

- **Defence in depth** — Prometheus does not provide a query-side injection guard; the only place to
  enforce safety is the client.
- **Curated templates** — substitution values are passed into templates the operator did not author.
  The substitution boundary is the right enforcement point.
- **Explicit denial path** — when a value fails validation, the query MUST NOT be issued and the
  operator MUST see a clear reason.
- **Compatibility with Kubernetes label rules** — the safe character set must intersect the
  realistic Kubernetes label-value alphabet.

## Considered options

1. **No validation** — rejected. Trivial injection surface.
2. **Escape special characters** — rejected. PromQL has no canonical escape; the language is
   context-sensitive and escape rules differ for double-quoted strings vs regex matchers.
3. **Whitelist regex applied to substitution values** — chosen.
4. **Parameterised query** — Prometheus HTTP API supports `?param=` form-encoded values; this is the
   preferred path where the template permits it. Whitelist regex remains the substitution-time
   guard.

## Pros and cons of the options

### Option 1 — No validation

- Bad, because Kubernetes label values permit characters (`}`, `|`, `~`, `+`) that are meaningful
  in PromQL, creating a trivial injection surface where a crafted resource name can escape the
  intended label matcher and issue arbitrary queries.

### Option 2 — Escape special characters

- Bad, because PromQL has no canonical escape syntax; escaping rules differ between double-quoted
  string literals and regex matchers, making a universal escaping function error-prone and
  context-dependent.

### Option 3 — Whitelist regex applied to substitution values (chosen)

- Good, because the allowed character set `^[a-zA-Z0-9._-]{1,63}$` is the intersection of
  Kubernetes RFC 1123 label values, DNS subdomain components, and characters safe inside PromQL
  string literals and regex matchers; it is enforced at the substitution boundary before any
  query construction.
- Good, because the Rego policy at the enforcement point is auditable, testable, and produces an
  explicit `PromQLInjectionAttemptBlocked` audit entry for every rejection.
- Bad, because resource names with characters outside the whitelist (valid in CRD names) cannot be
  queried via the templated dashboards; operators must use a free-form query view with an explicit
  guard for those names.

### Option 4 — Parameterised query (preferred complement)

- Good, because passing values via `?param=` form-encoded parameters to the Prometheus HTTP API
  prevents injection by construction — the URL encoding layer isolates the value from the query
  string.
- Bad, because not all PromQL templates can be parameterised at the Prometheus HTTP API level;
  the whitelist regex is still required for templates that cannot be rewritten to use parameter
  binding.

## Decision outcome

- **Allowed character set** for substitution values: `^[a-zA-Z0-9._-]{1,63}$`. This is the
  intersection of: Kubernetes RFC 1123 label values, DNS subdomain components, and characters
  unambiguously safe inside PromQL string literals and regex matchers. The 63-character upper bound
  matches Kubernetes label rules.
- **Enforcement point**: a Rego policy
  `docs/arch/contexts/metrics_observability/policies/metrics_policy.rego` evaluates every
  substitution value before query construction. The policy returns `deny[reason]` when any value
  falls outside the whitelist; the metrics client refuses to issue the query and surfaces the reason
  inline.
- **Label matchers**: when a value is interpolated into a label matcher (`=~"^<value>$"`), the value
  is anchored with `^` and `$` to prevent partial-match escape; the value itself is already
  whitelist-bounded.
- **Parameter binding preferred**: where the PromQL template can be rewritten to pass the value via
  `?param=` form-encoded parameters to the Prometheus HTTP API (e.g., as a label matcher in the
  `query=` parameter rather than via string interpolation), that form MUST be used. Whitelist regex
  is the substitution-time guard for templates that cannot be parameterised.
- **Curated templates only**: operators cannot author free-form PromQL for the templated dashboards.
  The curated set lives in compile-time constants.
- **Audit entry**: every rejected substitution writes a `PromQLInjectionAttemptBlocked` audit entry
  with the offending value digest, the template name, and the rejecting BC.

### Consequences

- **Positive** — injection surface closed at the substitution boundary; consistent denial path;
  audit trail.
- **Negative** — pod/namespace names with characters outside the whitelist (rare but legal in CRD
  names) cannot be queried via the templated dashboards; operator must use a free-form query view
  with explicit guard.
- **Neutral** — the curated PromQL template inventory is bounded; new templates added through ADR
  amendments.

### Confirmation

- Unit test: substitution value `prod}|drop_metric{` is rejected by the Rego policy with the
  expected reason.
- Integration test: simulated CRD with name `my.crd-resource_v1` succeeds; simulated name
  `my-${INJECT}-crd` is rejected.
- Audit log inspection: each rejection produces exactly one `PromQLInjectionAttemptBlocked` entry.
- The metrics client never issues a Prometheus HTTP request when the Rego policy denies; verified by
  mocked Prometheus server.

## More information

- ADR-0016 — Prometheus integration (curated PromQL templates).
- ADR-0025 — Per-cluster isolation (per-cluster Prometheus client binding).
- Rego policy: `docs/arch/contexts/metrics_observability/policies/metrics_policy.rego`.
- Gherkin scenario:
  `docs/arch/contexts/metrics_observability/features/lifecycle/query-injection-blocked.feature`.
