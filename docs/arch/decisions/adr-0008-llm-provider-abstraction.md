# ADR-0008 — LLM provider abstraction over Anthropic, OpenAI, and OpenAI-compatible endpoints

- Status — Accepted (ratified 2026-05-15)
- Refined by — ADR-0038
- Date — 2026-05-15
- Deciders — Fabricio Fonseca
- Consulted — (none yet)
- Informed — (none yet)
- Tags — llm, abstraction, hexagonal, anthropic, openai, ollama

> **Pinning note (2026-05-15).** The concrete adapter libraries adopted are pinned by **ADR-0019** —
> `jamesrochabrun/SwiftAnthropic` 2.2.2 for the Anthropic adapter, `MacPaw/OpenAI` 0.4.9 for both
> the OpenAI and OpenAI-compatible adapters (the latter via `baseURL` override). Both libraries are
> imported with `@preconcurrency` until upstream migrates to Swift 6 language mode.
> `Recouse/EventSource` 0.1.8 is the standby SSE parser for cases where direct `URLSession.bytes` is
> insufficient.

## Context and problem statement

K8sManager hosts an assistant that talks to one of several LLM providers. The three providers in
scope for MVP+ (ADR-0006) differ in:

- Wire format — Anthropic uses the Messages API (`messages`, `content` blocks, `stop_reason`);
  OpenAI uses Chat Completions or the Responses API (`messages` or `input`, `tool_calls`,
  `finish_reason`); OpenAI-compatible servers (Ollama, LM Studio, vLLM, OpenRouter) follow OpenAI's
  surface but vary in feature coverage.
- Streaming — Anthropic emits typed SSE events (`message_start`, `content_block_delta`,
  `message_delta`, `message_stop`); OpenAI emits SSE deltas inside a `data:` payload ended by
  `data: [DONE]`; OpenAI-compatible servers approximate the OpenAI stream but may omit `usage`
  deltas or `tool_calls`.
- Tool use — Anthropic's `tool_use` content blocks; OpenAI's `tool_calls` array with `function.name`
  and `function.arguments`; OpenAI-compatible coverage varies.
- Sampling parameters — `temperature`, `top_p`, `top_k`, `max_tokens`, `stop_sequences`, system
  prompt placement, and cache controls each have provider-specific quirks.

The domain core must speak one ubiquitous language for "send a message and stream the response"
without being aware of these differences. Adapters absorb the variance.

## Decision drivers

- **Hexagonal invariant** — the domain core never imports a vendor SDK or HTTP type.
- **Streaming as a first-class concern** — the UI updates as tokens arrive; cancellation must be
  cooperative.
- **Tool use semantics shared across providers** — the assistant reads and writes a single tool-use
  shape that adapters translate.
- **Configurability** — operators choose provider, base URL, model, temperature, top-p, max tokens,
  and a few advanced knobs without reaching beyond settings.
- **Privacy-friendly local** — OpenAI-compatible endpoints (Ollama, LM Studio) are equally
  first-class; the assistant works offline against a local model.

## Pros and cons of the options

### Option A — Custom port plus per-provider adapters (chosen)

- Good, because the hexagonal seam is clean: the domain core never imports a vendor SDK or HTTP type.
- Good, because adding a fourth provider requires only one new adapter and one new profile kind.
- Good, because offline local-model use (Ollama, LM Studio) is a first-class path, not an afterthought.
- Bad, because every new provider-specific feature (Anthropic prompt caching, OpenAI Responses API)
  must be lifted into the port as a `providerHints` hint before the UI can use it.

### Option B — Use an existing aggregator SDK (LiteLLM, LangChain.swift)

- Good, because N-provider coverage is obtained at no per-provider implementation cost.
- Bad, because it pulls in a large opaque dependency with an error model the codebase cannot control.
- Bad, because these SDKs are Python-first with thin, often non-idiomatic Swift bindings.

### Option C — Direct provider SDKs side by side

- Good, because each provider SDK exposes its best-in-class API surface directly.
- Bad, because three different mental models exist inside the assistant bounded context simultaneously.
- Bad, because OpenAI-compatible servers (Ollama, LM Studio) still require a bespoke adapter,
  delivering no savings over Option A for those cases.

## Decision outcome

Introduce a single domain-side port and a small family of adapters.

### Port (in the `llm_provider` domain core)

The port exposes a single asynchronous streaming entry point —
`func reply(to request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error>`.

- `AssistantRequest` carries a list of `AssistantMessage` values (`role`, ordered `content` parts),
  a list of declared `Tool` definitions, a `SamplingConfig` value object, and an application-level
  `cancellationToken`.
- `AssistantStreamEvent` is a sum type — `delta(textChunk)`, `toolUse(callId, name, jsonArguments)`,
  `toolUseFinish(callId, totalArguments)`, `usage(promptTokens, completionTokens)`,
  `finish(reason)`.
- `SamplingConfig` is a value object with `temperature`, `topP`, `topK`, `maxOutputTokens`,
  `stopSequences`, plus a `providerHints` map for provider-specific opt-ins (e.g., Anthropic's
  prompt-caching flag, OpenAI's `parallel_tool_calls`).

### Adapters (in the infrastructure layer)

- **AnthropicAdapter** — POSTs `/v1/messages` with `stream: true`, decodes typed SSE events,
  translates `tool_use` and `tool_result` content blocks to the port's `toolUse` events.
- **OpenAIAdapter** — POSTs Chat Completions or the Responses API (configurable per provider
  profile), decodes `data:` SSE chunks, flattens `tool_calls` deltas into the port's tool-use shape.
- **OpenAICompatibleAdapter** — same wire as OpenAI but allows arbitrary `baseURL`, skips fields not
  present (e.g., Ollama's missing `usage` deltas degrade gracefully to absent usage events), and
  exposes a feature-detection step that records which capabilities a profile actually offers.

### Provider profile

A `ProviderProfile` is a value object stored in `local_persistence` (ADR-0010) and is the
operator-facing unit of configuration. It carries:

- `kind` — `anthropic | openai | openai_compatible`.
- `displayName` — operator-chosen label.
- `baseURL` — required for `openai_compatible`, defaulted for the other two.
- `modelId` — provider's model identifier (e.g., `claude-sonnet-4-6`, `gpt-5.3`, `qwen3-32b`).
- `samplingDefaults` — a default `SamplingConfig`.
- `keyAlias` — reference (not the value) to a Keychain entry. The adapter resolves the key on demand
  and never logs it.

### Consequences

- **Positive** — the assistant code is provider-agnostic; adding a fourth provider is one adapter
  and one profile kind; offline use via Ollama is a first-class path.
- **Negative** — per-provider edge cases (Anthropic prompt caching, OpenAI Responses API streaming,
  OpenAI-compatible feature gaps) require small bespoke code paths inside their adapters; the port
  is the lowest common denominator and exposes capability hints rather than per-provider toggles.
- **Neutral** — provider-side rate limits are surfaced as a typed error variant; `assistant_chat`
  decides whether to retry, fail, or queue.

### Confirmation

- The `llm_provider` domain target compiles without importing any Anthropic or OpenAI SDK.
- A conformance test suite, parameterised by provider, asserts that each adapter emits the same
  `AssistantStreamEvent` sequence shape for an identical conceptual prompt.
- Switching the active `ProviderProfile` in settings causes the next assistant turn to use the new
  provider with no application restart.
- A cancellation issued via `cancellationToken` aborts the in-flight HTTP request within 200 ms on
  all three adapters.

## Considered options

### Option A — Custom port plus per-provider adapters (chosen)

- **Pros** — clean hexagonal seam; trivial to add providers; UI speaks one language.
- **Cons** — every new provider feature requires lifting it into the port (often as `providerHints`)
  before the UI can use it.

### Option B — Use an existing aggregator SDK (LiteLLM, LangChain.swift)

- **Pros** — coverage of N providers for free.
- **Cons** — pulls in a large dependency; opaque error model; often Python-first with thin Swift
  bindings; not idiomatic async/await.

### Option C — Direct provider SDKs side by side

- **Pros** — best-in-class per provider.
- **Cons** — three different mental models inside the assistant; no shared streaming protocol;
  OpenAI-compatible servers would still need a custom adapter anyway.

## More information

- ADR-0006 — Defines the `llm_provider` bounded context.
- ADR-0009 — MCP host plus in-process MCP server; tools surface flows from the assistant through the
  port defined here.
- ADR-0010 — Local persistence stores `ProviderProfile`; Keychain stores `apiKey` resolved via
  `keyAlias`.
- ADR-0011 — Swift concurrency conventions (`AsyncThrowingStream`, cooperative cancellation).
