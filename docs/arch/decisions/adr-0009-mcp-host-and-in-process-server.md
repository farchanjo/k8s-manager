# ADR-0009 — MCP host plus an in-process MCP server exposing read-only Kubernetes tools

- Status — Proposed; transport library pinned by ADR-0019
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — mcp, model-context-protocol, kubernetes, tool-use, assistant

> **Pinning note (2026-05-15).** The MCP host and in-process server use
> the official **`modelcontextprotocol/swift-sdk`** (version 0.12.1)
> with its `InMemoryTransport` — a pair of `AsyncStream` instances
> wired directly between host and server inside the same process.
> Spec evolution is tracked by version-pinning the SDK; the wire
> protocol is preserved so external stdio-based MCP servers can be
> added later without changing the host contract.

## Context and problem statement

The assistant (`assistant_chat`) needs to call Kubernetes operations
to answer "professional analysis" questions ("what is happening in
this cluster?", "why is this deployment failing?", "summarise the
events for namespace prod over the last hour"). Two architectures
are common:

(a) **Inline tool functions** — the assistant runtime defines tool
schemas inline in the LLM request and dispatches them to Swift
functions through a tagged-union router; no protocol involved.

(b) **Model Context Protocol (MCP)** — the assistant runs as a
**host** that consumes tools from one or more **MCP servers**.
Servers can be external subprocesses (`mcp-k8s-go`, `kubectl-mcp`)
or in-process implementations sharing the host's address space.

The product direction is to align with the MCP ecosystem so future
external MCP servers (Linear, GitHub, Grafana, etc.) can be added
without rewriting the assistant. We also want to ship K8s tools
ourselves so we can enforce a strict read-only policy and have
direct access to the existing `cluster_connectivity` pool.

## Decision drivers

- **Auditability** — the operator (and any future security review)
  must be able to read a single registry to know exactly which
  Kubernetes operations the assistant can invoke.
- **Read-only invariant** — no MVP+ tool may mutate the cluster.
  Mutating tools require an explicit ADR before they ship.
- **No external dependency at install time** — `mcp-k8s-go` and
  similar external servers would require the operator to install
  a binary and trust its update channel; in-process keeps the
  trust boundary inside the application bundle.
- **Future-proofing** — when external MCP servers become useful,
  the host should be able to consume them without changes to the
  assistant.

## Decision outcome

- K8sManager is an **MCP host**. The host implementation lives in
  `assistant_chat` and is provider-agnostic (it converts tool-use
  events from `llm_provider` into MCP tool calls).
- K8sManager runs an **in-process MCP server** owned by
  `cluster_intelligence`. The server speaks the standard MCP wire
  protocol over an in-process transport (a Swift `AsyncStream`
  pair) — no stdio, no socket. The same protocol surface allows
  swapping in stdio-based external servers later without touching
  the host.
- The in-process server exposes **read-only tools** only. The MVP+
  registry is:
  - `kube_list_pods(namespace?, labelSelector?, fieldSelector?, limit?)`
  - `kube_describe(kind, namespace, name)`
  - `kube_get_yaml(kind, namespace, name)`
  - `kube_events(namespace?, since?, limit?)`
  - `kube_logs(namespace, podName, containerName?, tailLines?, sinceSeconds?, follow=false)`
  - `kube_top_pods(namespace?)` (when `metrics.k8s.io` is available;
    surfaces a graceful "metrics-server not installed" error otherwise)
  - `kube_cluster_info()` (returns version, node count, namespace
    count, default service-account information)
- Every tool call passes through a **policy gate** defined in
  `contexts/cluster_intelligence/policies/`. The policy MUST deny
  any verb outside `{get, list, watch}` and any resource not in
  the read-only allow-list.
- Tool **inputs** are validated against the tool's MCP JSON-Schema;
  outputs are normalised to UTF-8 JSON with a maximum body of
  256 KiB (truncated with a trailing
  `{"_truncated": true, "_omittedBytes": N}` marker rather than
  raising).
- The host exposes a **tool-confirmation hook** — by default the
  read-only tools execute without prompting; the operator can opt
  in to "ask before each tool call" in settings.
- The host supports loading **external MCP servers in v1.x** (out
  of MVP+ scope). The contract is unchanged; only the transport
  differs.

### Consequences

- **Positive** — the assistant's surface area against Kubernetes is
  a small, explicit, gated registry; no external binary; ready to
  consume external MCP servers later; the policy gate doubles as a
  reusable audit log.
- **Negative** — implementing the MCP wire protocol (and keeping it
  current with upstream spec evolution) is non-trivial; the
  in-process transport is bespoke and must be kept aligned with
  any future stdio-based transport.
- **Neutral** — the in-process server is a separate Swift target
  consumed by `assistant_chat` only through the MCP host, never
  via direct function calls. This is intentional and keeps the
  decoupling honest.

### Confirmation

- The `cluster_intelligence` domain target exposes only an MCP
  server descriptor; nothing in `assistant_chat` imports it as a
  Swift module beyond the protocol-shaped host adapter.
- A negative test asserts that a request to a tool called
  `kube_delete_pod` returns a typed "tool not registered" error
  before reaching `cluster_connectivity`.
- A negative test forges a request that bypasses the input
  validator and asserts that the policy gate denies it.
- The MCP wire log is auditable via the diagnostics panel; entries
  redact bearer tokens and labels containing the substring
  `secret`.

## Considered options

### Option A — MCP host plus in-process MCP server (chosen)

- **Pros** — auditable registry; no external binary at install
  time; future external MCP servers are pluggable; clean
  separation between tool-calling protocol and Kubernetes
  connectivity.
- **Cons** — implementing MCP server-side is non-trivial.

### Option B — Inline tool functions, no MCP protocol

- **Pros** — least code; fastest to ship.
- **Cons** — no path to external MCP servers without a rewrite;
  no shared wire log; the policy gate must live alongside the
  inline router, which is easy to bypass during refactors.

### Option C — Spawn an external MCP server (`mcp-k8s-go`)

- **Pros** — zero implementation; battle-tested.
- **Cons** — operator must install and update a separate binary;
  trust boundary expands; current external servers carry write
  verbs that we would have to disable through filtering rather
  than design.

### Option D — Inline today, MCP later

- **Pros** — defers complexity.
- **Cons** — the migration cost is the same code, postponed; the
  inline registry tends to grow ad-hoc and resists clean
  protocolisation later.

## More information

- ADR-0003 — Read-only model for Kubernetes operations remains in
  effect; the MCP tools never mutate the cluster.
- ADR-0006 — Defines the `cluster_intelligence` bounded context.
- ADR-0008 — LLM provider abstraction; tool-use events translate
  into MCP tool calls in the host.
- ADR-0010 — Local persistence stores the MCP wire log (truncated)
  and per-tool execution counters.
