// Domain/AssistantStreamEvent.swift — llm_provider bounded context
// DDD role: ValueObject (sum type)
// CUE source: docs/arch/contexts/llm_provider/schemas/assistant_stream_event.cue

import Foundation

// MARK: - AssistantStreamEvent

/// Normalised event emitted by every LLM adapter.
///
/// Mirrors `#AssistantStreamEvent` from `assistant_stream_event.cue`. The
/// `assistant_chat` context consumes this enum without caring which provider
/// produced it. Each stream MUST emit exactly one `finish` event as its last
/// element and at most one `usage` event.
public enum AssistantStreamEvent: Sendable {
    /// A chunk of assistant-visible text.
    case delta(DeltaEvent)

    /// A tool call begins; full arguments arrive via subsequent `toolUseDelta`
    /// events and are finalised by `toolUseFinish`.
    case toolUseStart(ToolUseStartEvent)

    /// Incremental JSON fragment for an in-flight tool call.
    case toolUseDelta(ToolUseDeltaEvent)

    /// Tool call argument stream is complete.
    case toolUseFinish(ToolUseFinishEvent)

    /// Token usage report. Emitted at most once per stream.
    case usage(UsageEvent)

    /// Stream termination marker. Always the last event.
    case finish(FinishEvent)
}

// MARK: - DeltaEvent

/// A text chunk from the streaming completion.
///
/// Mirrors `#DeltaEvent` from `assistant_stream_event.cue`.
public struct DeltaEvent: Sendable {
    /// Incremental text fragment.
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

// MARK: - ToolUseStartEvent

/// Announces the start of a tool call.
///
/// Mirrors `#ToolUseStartEvent` from `assistant_stream_event.cue`.
public struct ToolUseStartEvent: Sendable {
    /// Correlation identifier. Matches subsequent `ToolUseDeltaEvent` and
    /// `ToolUseFinishEvent` payloads.
    public let callId: String

    /// Tool name as advertised via `ToolDefinition`.
    public let name: String

    public init(callId: String, name: String) {
        self.callId = callId
        self.name = name
    }
}

// MARK: - ToolUseDeltaEvent

/// Incremental JSON fragment for an in-flight tool call.
///
/// Mirrors `#ToolUseDeltaEvent` from `assistant_stream_event.cue`.
public struct ToolUseDeltaEvent: Sendable {
    /// Matches the `callId` from the preceding `ToolUseStartEvent`.
    public let callId: String

    /// Partial UTF-8 JSON string. Accumulate in order to reconstruct the full
    /// arguments object.
    public let jsonChunk: String

    public init(callId: String, jsonChunk: String) {
        self.callId = callId
        self.jsonChunk = jsonChunk
    }
}

// MARK: - ToolUseFinishEvent

/// Signals that the tool argument stream is complete.
///
/// Mirrors `#ToolUseFinishEvent` from `assistant_stream_event.cue`.
public struct ToolUseFinishEvent: Sendable {
    /// Matches the `callId` from the preceding `ToolUseStartEvent`.
    public let callId: String

    /// The fully assembled JSON argument object.
    public let totalArguments: String

    public init(callId: String, totalArguments: String) {
        self.callId = callId
        self.totalArguments = totalArguments
    }
}

// MARK: - UsageEvent

/// Token usage report emitted at most once per stream.
///
/// Mirrors `#UsageEvent` from `assistant_stream_event.cue`. Adapters that do
/// not report usage skip this event entirely.
public struct UsageEvent: Sendable {
    /// Tokens consumed by the prompt (including any injected system prompt).
    public let promptTokens: Int

    /// Tokens generated in the completion.
    public let completionTokens: Int

    /// Prompt tokens served from the provider's prompt cache. Absent implies
    /// zero.
    public let cachedPromptTokens: Int?

    public init(
        promptTokens: Int,
        completionTokens: Int,
        cachedPromptTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cachedPromptTokens = cachedPromptTokens
    }
}

// MARK: - FinishReason

/// Why the stream ended.
///
/// Mirrors the `reason` discriminant in `#FinishEvent`.
public enum FinishReason: String, Sendable {
    /// Natural stop — model reached a stop sequence or end-of-generation.
    case stop

    /// The `maxOutputTokens` cap was hit before the model stopped naturally.
    case maxTokens = "max_tokens"

    /// The model yielded control to invoke one or more tools.
    case toolUse = "tool_use"

    /// The provider returned an error condition.
    case error

    /// The request was cancelled by the consumer's `Task`.
    case cancelled
}

// MARK: - FinishEvent

/// Stream termination marker.
///
/// Mirrors `#FinishEvent` from `assistant_stream_event.cue`. Always the last
/// event emitted. `detail` is populated only for `error` and `cancelled`
/// reasons. It MUST NOT contain credential material.
public struct FinishEvent: Sendable {
    /// Termination reason.
    public let reason: FinishReason

    /// Human-readable detail for `error` and `cancelled` reasons; `nil`
    /// otherwise.
    public let detail: String?

    public init(reason: FinishReason, detail: String? = nil) {
        self.reason = reason
        self.detail = detail
    }
}

// MARK: - AssistantRequest

/// Input to `LLMStreamingPort.reply(to:)`.
///
/// Carries the conversation history, tool registry for this turn, an optional
/// sampling override, and task-scoped cancellation via the caller's `Task`.
public struct AssistantRequest: Sendable {
    /// Ordered conversation history.
    public let messages: [AssistantMessage]

    /// Tools advertised to the model for this turn. Empty means no tool use.
    public let tools: [ToolDefinition]

    /// Sampling override. When `nil` the provider uses the profile defaults.
    public let samplingOverride: SamplingConfig?

    /// Profile identifier selected for this request.
    public let profileId: UUID

    public init(
        messages: [AssistantMessage],
        tools: [ToolDefinition] = [],
        samplingOverride: SamplingConfig? = nil,
        profileId: UUID
    ) {
        self.messages = messages
        self.tools = tools
        self.samplingOverride = samplingOverride
        self.profileId = profileId
    }
}
