// Domain/AssistantMessage.swift — llm_provider bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/llm_provider/schemas/assistant_message.cue

import Foundation

// MARK: - MessagePart

/// A sum type over the content shapes a provider turn may carry.
///
/// Mirrors `#MessagePart` from `assistant_message.cue`. Adapters degrade
/// gracefully when a provider does not support a specific shape (e.g., omitting
/// `cacheControl` for non-Anthropic providers).
public enum MessagePart: Hashable, Sendable, Codable {
    /// A plain-text span, optionally marked for prompt-cache pinning.
    case text(TextPart)

    /// A completed tool invocation embedded in an assistant turn.
    case toolUse(ToolUsePart)

    /// The result returned to the model after a tool execution.
    case toolResult(ToolResultPart)
}

// MARK: - TextPart

/// Plain-text content part.
///
/// Mirrors `#TextPart` from `assistant_message.cue`.
public struct TextPart: Hashable, Sendable, Codable {
    /// The text content.
    public let text: String

    /// When set, instructs Anthropic adapters to pin this block as a
    /// prompt-cache boundary. Ignored by adapters that do not support caching.
    public let cacheControl: CacheControl?

    public init(text: String, cacheControl: CacheControl? = nil) {
        self.text = text
        self.cacheControl = cacheControl
    }
}

/// Prompt-cache control marker. Currently only `ephemeral` is defined.
public enum CacheControl: String, Hashable, Sendable, Codable {
    case ephemeral
}

// MARK: - ToolUsePart

/// A tool call embedded in an assistant turn (model → tool).
///
/// Mirrors `#ToolUsePart` from `assistant_message.cue`. `jsonArguments` is a
/// fully buffered UTF-8 JSON object; streaming adapters accumulate delta chunks
/// before producing this part.
public struct ToolUsePart: Hashable, Sendable, Codable {
    /// Correlation identifier matching the corresponding `ToolResultPart`.
    public let callId: String

    /// The tool name as advertised in `ToolDefinition`.
    public let name: String

    /// Fully buffered UTF-8 JSON object of tool arguments.
    public let jsonArguments: String

    public init(callId: String, name: String, jsonArguments: String) {
        self.callId = callId
        self.name = name
        self.jsonArguments = jsonArguments
    }
}

// MARK: - ToolResultPart

/// The result returned to the model after executing a tool (tool → model).
///
/// Mirrors `#ToolResultPart` from `assistant_message.cue`. The MCP server caps
/// `jsonResult` at 256 KiB and appends a truncation marker when needed.
public struct ToolResultPart: Hashable, Sendable, Codable {
    /// Matches the `callId` from the originating `ToolUsePart`.
    public let callId: String

    /// UTF-8 JSON body returned by the tool.
    public let jsonResult: String

    /// `true` when the tool returned an error rather than a value.
    public let isError: Bool

    public init(callId: String, jsonResult: String, isError: Bool) {
        self.callId = callId
        self.jsonResult = jsonResult
        self.isError = isError
    }
}

// MARK: - AssistantMessage

/// One wire-agnostic conversation turn.
///
/// Mirrors `#AssistantMessage` from `assistant_message.cue`. Adapters
/// translate this into Anthropic content blocks, OpenAI Chat Completions
/// messages, or compatible variants.
public struct AssistantMessage: Hashable, Sendable, Codable {
    /// Conversation participant for this turn.
    public let role: MessageRole

    /// Ordered content parts. Must be non-empty.
    public let content: [MessagePart]

    public init(role: MessageRole, content: [MessagePart]) {
        self.role = role
        self.content = content
    }
}

// MARK: - MessageRole

/// The conversational role for a message turn.
///
/// Mirrors the `role` discriminant in `#AssistantMessage`.
public enum MessageRole: String, Hashable, Sendable, Codable {
    case system
    case user
    case assistant
    case tool
}

// MARK: - ToolDefinition

/// Schema advertised to the provider for one assistant request.
///
/// Mirrors `#ToolDefinition` from `assistant_message.cue`. Not persisted;
/// derived from the MCP server registry at request time.
public struct ToolDefinition: Hashable, Sendable, Codable {
    /// Tool name matching `^[a-z][a-z0-9_]{0,63}$`.
    public let name: String

    /// Human-readable description of what the tool does.
    public let description: String

    /// JSON Schema (draft-2020-12) for the tool inputs encoded as a UTF-8
    /// string. Adapters translate this into the provider's tool format.
    public let inputJSONSchema: String

    public init(name: String, description: String, inputJSONSchema: String) {
        self.name = name
        self.description = description
        self.inputJSONSchema = inputJSONSchema
    }
}
