// Domain/ChatMessage.swift — assistant_chat bounded context
// DDD role: Entity
// CUE source: docs/arch/contexts/assistant_chat/schemas/chat_message.cue

import Foundation
import SharedKernel

// MARK: - MessageRole

/// Role of the party that authored a chat message.
///
/// Mirrors the `role` discriminant from `chat_message.cue`.
public enum MessageRole: String, Hashable, Sendable, Codable {
    case system
    case user
    case assistant
}

// MARK: - FinishReason

/// Provider-reported reason why the assistant stopped generating tokens.
///
/// Mirrors the `finishReason` discriminant from `chat_message.cue`.
public enum FinishReason: String, Hashable, Sendable, Codable {
    case stop
    case maxTokens = "max_tokens"
    case toolUse = "tool_use"
    case error
    case cancelled
}

// MARK: - UsageRecord

/// Provider-reported token accounting for one assistant turn.
///
/// Mirrors `#UsageRecord` from `chat_message.cue`. Immutable (ValueObject).
public struct UsageRecord: Hashable, Sendable, Codable {
    /// Tokens in the prompt sent to the provider.
    public let promptTokens: Int
    /// Tokens in the completion returned by the provider.
    public let completionTokens: Int
    /// Prompt tokens served from the provider's KV cache, if reported.
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

// MARK: - ChatMessage

/// One persisted message inside a `ChatSession`.
///
/// Mirrors `#ChatMessage` from `chat_message.cue`. Tool-use and tool-result
/// content is captured in `ToolCallRecord` rather than nested here, so this
/// entity remains a stable log entry independent of tool execution outcomes.
public struct ChatMessage: Hashable, Sendable, Codable {
    /// UUIDv7 unique within the parent session.
    public let id: UUID

    /// UUIDv7 of the owning `ChatSession`.
    public let sessionId: UUID

    /// Zero-based turn index within the session.
    public let turn: Int

    /// RFC 3339 timestamp when this message was created.
    public let createdAtRFC3339: String

    /// The party that authored this message.
    public let role: MessageRole

    /// Textual content. Tool calls reference this message via
    /// `ToolCallRecord.parentMessageId`.
    public let content: String

    /// `true` while the assistant is still producing tokens; `false` on finish
    /// or cancellation. At most one message per session has `streaming=true`.
    public let streaming: Bool

    /// Provider-reported finish reason, set once `streaming` becomes `false`.
    public let finishReason: FinishReason?

    /// Token accounting reported by the provider, if available.
    public let usage: UsageRecord?

    public init(
        id: UUID = UUIDv7.generate(),
        sessionId: UUID,
        turn: Int,
        createdAtRFC3339: String,
        role: MessageRole,
        content: String,
        streaming: Bool = false,
        finishReason: FinishReason? = nil,
        usage: UsageRecord? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.turn = turn
        self.createdAtRFC3339 = createdAtRFC3339
        self.role = role
        self.content = content
        self.streaming = streaming
        self.finishReason = finishReason
        self.usage = usage
    }
}
