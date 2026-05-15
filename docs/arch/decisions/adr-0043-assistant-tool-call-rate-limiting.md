# ADR-0043 — Per-session assistant tool-call rate limiting

- Status — Accepted (ratified 2026-05-15)
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — assistant, mcp, rate-limit, policy, assistant_chat, cluster_intelligence

## Context and problem statement

The in-process MCP host (ADR-0009) exposes Kubernetes read-only tools to the assistant. Without a
per-session quota, a runaway model loop or adversarial prompt can issue dozens of `kube_*` tool
calls per second, exhausting the cluster API budget, generating noise in audit logs, and inflating
Kubernetes API server load shared with the rest of the operator's workflow. The Gherkin lifecycle
scenario `docs/arch/contexts/assistant_chat/features/lifecycle/rate-limit-per-session.feature`
already exercises this behaviour but no ADR defines the limit, the queue semantics, or the rejection
contract.

## Decision drivers

- **Cluster API server protection** — bounded tool-call rate per conversation prevents per-session
  API storms.
- **Predictable assistant cost** — operator can reason about how many tool calls a single chat
  session can issue.
- **Audit log volume** — every tool call writes an `mcp_wire_log` entry (ADR-0010); unbounded calls
  inflate persistence cost.
- **No silent failure** — when the limit is reached, the model and the operator MUST see an explicit
  error envelope, not a hang.

## Considered options

1. **No limit** — rejected. Cluster API server abuse surface.
2. **Global app-wide limit** — rejected. Multi-cluster operators legitimately drive higher
   throughput in parallel sessions.
3. **Per-session sliding window with explicit error envelope** — chosen.
4. **Per-tool quota** — rejected for MVP++. Adds complexity without clear benefit; can be layered
   later.

## Decision outcome

- **Limit**: 20 tool invocations per rolling 60-second window per `AssistantChatSession`. The window
  is per-session, sliding, computed in memory.
- **Enforcement**: when a new tool invocation would exceed the limit, the MCP host returns an
  `mcp.tool_rate_limited` error envelope (`{code: "rate_limited", retryAfterSeconds: <n>}`) instead
  of executing the tool. The model receives this as a `tool_result` with the error structure and can
  decide to wait or to inform the user.
- **No queueing**: rejected calls are NOT queued. The model receives the error immediately and is
  responsible for back-off behaviour.
- **Window reset**: at session close, the in-memory counter is discarded. The next session for the
  same operator starts with a full budget.
- **Override**: operator may temporarily raise the limit to 60 invocations/minute via a settings
  toggle for an active session; this raises an `AssistantRateLimitOverride` audit entry. The toggle
  does not persist across launches.
- **Confirmation token tools** (operator-confirmed cluster writes via `cluster_intelligence`) are
  NOT counted against this limit because they require explicit operator gesture; the assistant
  cannot drive them autonomously.

### Consequences

- **Positive** — bounded API server load per session; observable failure mode; operator override for
  power users.
- **Negative** — long analytical conversations may hit the limit and require the operator to wait or
  override; the 20/minute number is a design heuristic and may need adjustment after telemetry.
- **Neutral** — the limit applies only to MCP read-only tools; confirmation-token mutations are out
  of scope.

### Confirmation

- Integration test issues 20 successful invocations within 30s, then the 21st returns
  `mcp.tool_rate_limited` with `retryAfterSeconds` pointing to the next available window slot.
- After 60s elapse from the first invocation, a new invocation succeeds.
- Operator override raises the cap to 60; test issues 60 within 60s; the 61st returns
  `mcp.tool_rate_limited`.
- Audit log inspection: `AssistantRateLimitOverride` entry recorded when override engaged.

## More information

- ADR-0008 — LLM provider abstraction.
- ADR-0009 — MCP host and in-process MCP server.
- ADR-0010 — Local persistence (audit log surface).
- ADR-0012 — Mutating operations policy (confirmation tokens excluded from this limit).
- Gherkin scenario:
  `docs/arch/contexts/assistant_chat/features/lifecycle/rate-limit-per-session.feature`.
