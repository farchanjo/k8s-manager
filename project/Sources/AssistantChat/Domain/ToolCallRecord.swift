// Domain/ToolCallRecord.swift — assistant_chat bounded context
// DDD role: Entity
// CUE source: docs/arch/contexts/assistant_chat/schemas/chat_message.cue (#ToolCallRecord)

import Foundation

// MARK: - ToolCallStatus

/// Lifecycle state of one tool-use round trip.
///
/// Mirrors the `status` discriminant from `#ToolCallRecord` in
/// `chat_message.cue`. State transitions are append-only in the
/// persistence log.
public enum ToolCallStatus: String, Hashable, Sendable, Codable {
    /// The model requested the tool; the dispatcher has not started yet.
    case requested
    /// The dispatcher is executing the tool via the MCP server.
    case running
    /// The tool completed and a valid result is available.
    case succeeded
    /// The tool was blocked by the policy gate (ADR-0009); no MCP call made.
    case deniedByPolicy = "denied_by_policy"
    /// The MCP server returned an error or the call timed out.
    case failed
    /// The user or session actor cancelled the turn before this call completed.
    case cancelled
}

// MARK: - ToolCallRecord

/// Persisted log entry for one tool-use round trip inside a `ChatSession`.
///
/// Mirrors `#ToolCallRecord` from `chat_message.cue`. Linked to the
/// triggering assistant message via `parentMessageId`.
public struct ToolCallRecord: Hashable, Sendable, Codable {
    /// Opaque call identifier as produced by the provider stream (1–128
    /// alphanumeric/hyphen/underscore characters).
    public let callId: String

    /// UUIDv7 of the owning `ChatSession`.
    public let sessionId: UUID

    /// UUIDv7 of the assistant `ChatMessage` that triggered this call.
    public let parentMessageId: UUID

    /// Registered tool name (lowercase, max 64 characters).
    public let toolName: String

    /// RFC 3339 timestamp when the model emitted the tool-use request.
    public let requestedAtRFC3339: String

    /// RFC 3339 timestamp when the call reached a terminal state, if any.
    public let completedAtRFC3339: String?

    /// Verbatim assembled arguments JSON string produced by the model.
    public let argumentsJSON: String

    /// Tool result JSON string (truncated to 256 KiB by the MCP server).
    public let resultJSON: String?

    /// Current lifecycle status.
    public let status: ToolCallStatus

    /// Operator-facing detail when `status` is `deniedByPolicy` or `failed`.
    public let detail: String?

    public init(
        callId: String,
        sessionId: UUID,
        parentMessageId: UUID,
        toolName: String,
        requestedAtRFC3339: String,
        completedAtRFC3339: String? = nil,
        argumentsJSON: String,
        resultJSON: String? = nil,
        status: ToolCallStatus = .requested,
        detail: String? = nil
    ) {
        self.callId = callId
        self.sessionId = sessionId
        self.parentMessageId = parentMessageId
        self.toolName = toolName
        self.requestedAtRFC3339 = requestedAtRFC3339
        self.completedAtRFC3339 = completedAtRFC3339
        self.argumentsJSON = argumentsJSON
        self.resultJSON = resultJSON
        self.status = status
        self.detail = detail
    }
}
