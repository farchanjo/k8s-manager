# Bounded Context — `llm_provider`

## Purpose

Own the model of "talk to an LLM provider and stream a normalised
reply". This context abstracts Anthropic, OpenAI, and any
OpenAI-compatible endpoint behind a single port and exposes
operator-facing configuration for each provider profile.

## Ubiquitous language

- **Provider profile** — one operator-configured entry binding a
  provider kind, a model identifier, default sampling parameters,
  and a reference to a Keychain entry holding the API key.
- **Provider kind** — one of `anthropic`, `openai`,
  `openai_compatible`.
- **Sampling config** — temperature, top-p, top-k, max output
  tokens, stop sequences, and a free-form provider-hints map.
- **Assistant request** — the input to the provider port — an
  ordered list of `AssistantMessage` plus declared tools, sampling,
  and a cancellation token.
- **Assistant message** — one wire-agnostic conversation turn with
  a role and ordered content parts (`text`, `tool_use`,
  `tool_result`).
- **Assistant stream event** — the normalised event emitted by an
  adapter — `delta`, `tool_use_start`, `tool_use_delta`,
  `tool_use_finish`, `usage`, `finish`.

## Tactical roles

- **`ProviderProfile`** — AggregateRoot. Persisted by
  `local_persistence`. Identifies a key by `keyAlias` only.
- **`SamplingConfig`** — ValueObject.
- **`AssistantMessage`** — ValueObject.
- **`MessagePart`** — ValueObject (sum type over `text`,
  `tool_use`, `tool_result`).
- **`AssistantStreamEvent`** — ValueObject (sum type).
- **`ToolDefinition`** — ValueObject — the schema advertised to the
  provider for one assistant turn.
- **`LLMProviderPort`** — Port. Single async-streaming entry point
  `func reply(to request: AssistantRequest) -> AsyncThrowingStream<AssistantStreamEvent, Error>`.
- **`LLMKeyResolverPort`** — Port. Reads the secret value from
  Keychain by `keyAlias`. The default adapter lives in
  `local_persistence`.

## Adapters (infrastructure)

- **AnthropicAdapter** — `POST /v1/messages` with `stream: true`,
  typed SSE event decoder, prompt-caching support via
  `providerHints`.
- **OpenAIAdapter** — Chat Completions or Responses API with SSE
  delta decoding and `tool_calls` flattening.
- **OpenAICompatibleAdapter** — OpenAI wire format with a
  configurable `baseURL`, a feature-detection step on profile save,
  and graceful degradation when fields are absent.

## Dependencies

- Consumes `LLMKeyResolverPort` to obtain API key values; never
  stores or logs them.
- Depends on the shared kernel for clock and UUID generation.

## Read models exposed to other contexts

- `ProviderListReadModel` — flat list of profiles with display name,
  kind, model, and "last verified" status. Consumed by `app_shell`
  for the settings surface.
- `ProviderCapabilityReadModel` — what features a profile is known
  to support after feature detection. Consumed by `assistant_chat`
  to decide whether to advertise tools.

## Invariants

- `ProviderProfile.kind = openai_compatible` requires `baseURL` set.
- API keys never appear in any persisted record outside Keychain.
- API keys never appear in any log entry, telemetry payload, or
  diagnostics export.
- Cancellation propagates from the consumer's `Task` to the
  underlying HTTP request within 200 ms.
- The adapter MUST emit at most one `usage` event per stream.

## Out of scope

- Conversation state and tool-use loop policy — see `assistant_chat`.
- Tool execution — see `cluster_intelligence` (the MCP server).
- Bedrock and Vertex providers — deferred to v1.x.
