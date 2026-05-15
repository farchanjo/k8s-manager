# Bounded Context — `assistant_chat`

## Purpose

Own the model of "a single conversation with the assistant" — its session, its persistent message
log, its tool-use loop, its streaming and cancellation semantics, and the policy for surfacing
declared tools to the LLM. This context is the **MCP host** in the sense of ADR-0009.

## Ubiquitous language

- **Chat session** — one named conversation, bound to a single provider profile and optionally
  pinned to a Kubernetes context.
- **Turn** — one (user, assistant) message pair. The turn may contain zero or more tool calls
  between the user message and the final assistant message.
- **Tool-use loop** — the inner loop that alternates LLM stream events with MCP tool calls until the
  model finishes without requesting another tool.
- **Tool call record** — the persisted log entry of one tool-use round trip — arguments, result,
  timing, outcome.
- **System prompt** — the persistent instruction at the head of the message list. Editable per
  session.
- **Pinned Kubernetes context** — an optional binding from the session to a single `ContextId` from
  `context_navigation`; the MCP server uses this to scope tool calls.

## Tactical roles

- **`ChatSession`** — AggregateRoot.
- **`ChatMessage`** — Entity inside the session.
- **`ToolCallRecord`** — Entity inside the session, indexed by `callId`.
- **`UsageRecord`** — ValueObject embedded in `ChatMessage`.
- **`AssistantSessionActor`** — DomainService implemented as a per-session actor (ADR-0011). Owns
  the in-flight stream state and orchestrates the tool-use loop.
- **`ToolDispatcher`** — DomainService. Takes a tool-use event from the LLM stream, looks the tool
  up in the in-process MCP server's registry, executes it with the pinned cluster context, and
  translates the result back into a `tool_result` part for the next provider turn.
- **`ChatRepositoryPort`** — Port. Persists sessions, messages, tool-call records. Default adapter
  wired to `local_persistence`.

## Dependencies

- Consumes `LLMProviderPort` from `llm_provider` for streaming replies.
- Consumes the in-process MCP server (a port) from `cluster_intelligence` for tool execution.
- Consumes `ContextRepositoryPort` to resolve the pinned `ContextId` to a current `ClusterId`.
- Persists through `ChatRepositoryPort` adapted by `local_persistence`.

```mermaid
sequenceDiagram
    participant ui as UI
    participant actor as AssistantSessionActor
    participant llm as LLMProviderPort
    participant dispatcher as ToolDispatcher
    participant mcp as MCPServer

    ui->>actor: send(userMessage)
    actor->>llm: reply(AssistantRequest)
    loop tool-use loop
        llm-->>actor: AssistantStreamEvent(tool_use_start)
        llm-->>actor: AssistantStreamEvent(tool_use_delta)
        llm-->>actor: AssistantStreamEvent(tool_use_finish)
        actor->>dispatcher: dispatch(toolUseEvent)
        dispatcher->>mcp: call(toolName, args, pinnedContextId)
        mcp-->>dispatcher: ToolResult
        dispatcher-->>actor: tool_result part
        actor->>llm: reply(AssistantRequest + tool_result)
    end
    llm-->>actor: AssistantStreamEvent(finish)
    actor-->>ui: LiveTurnReadModel(complete)
```

## Read models exposed to other contexts

- `OpenSessionsReadModel` — sessions filtered by `status="active"` ordered by `updatedAtRFC3339`
  descending. Consumed by `app_shell` for the session list.
- `LiveTurnReadModel` — the current streaming state of one session (tokens so far, pending tool
  calls, finish flag). Consumed by the active chat view.

## Invariants

- The `AssistantChat` domain core never imports `SwiftAnthropic`, `MacPaw/OpenAI`,
  `modelcontextprotocol/swift-sdk`, `GRDB`, or any Foundation networking type. Provider streaming,
  MCP host wiring, and persistence access cross the relevant domain ports (`LLMProviderPort`,
  `MCPHostPort`, `ChatRepositoryPort`) only.
- A `ChatSession` is bound to exactly one `ProviderProfile` at any time; changing it is an explicit
  operator action.
- A `ChatMessage` with `streaming=true` is always the most recent message of its session; only one
  such message exists per session.
- Tool calls execute only against tools registered in the MCP server (ADR-0009); requests for
  unregistered tools persist a `denied_by_policy` `ToolCallRecord` and continue the loop with a
  tool-result that names the denial.
- Cancellation propagates from the UI through the session actor to the provider's HTTP request
  **and** to any in-flight tool call.
- Streaming events are buffered with `bufferingOldest(16)` for `delta` events to keep memory bounded
  under fast streams.

## Out of scope

- Provider wire format and feature detection — see `llm_provider`.
- Tool implementation and policy gating — see `cluster_intelligence`.
- Persistence schema and migrations — see `local_persistence`.
- Multimodal attachments (images, video) — deferred past MVP+.
