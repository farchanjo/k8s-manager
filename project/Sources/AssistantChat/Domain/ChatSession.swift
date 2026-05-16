// Domain/ChatSession.swift — assistant_chat bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/assistant_chat/schemas/chat_session.cue

import Foundation
import SharedKernel

// MARK: - SessionStatus

/// Lifecycle status of a chat session visible in the sidebar.
///
/// Mirrors the `status` discriminant from `chat_session.cue`.
public enum SessionStatus: String, Hashable, Sendable, Codable, CaseIterable {
    /// Session is open in the UI and accepting new turns.
    case active
    /// Session is hidden from the sidebar but not deleted.
    case archived
    /// Session is pending deletion.
    case trash
}

// MARK: - ChatSession

/// Aggregate root for one assistant conversation.
///
/// Mirrors `#ChatSession` from `chat_session.cue`. Bound to exactly one
/// `ProviderProfile` at creation; optionally pinned to a Kubernetes context
/// that biases the assistant's tool calls toward that cluster.
public struct ChatSession: Hashable, Sendable, Codable {
    /// UUIDv7 for this session instance.
    public let id: UUID

    /// Human-readable session title (1–120 characters).
    public let title: String

    /// The `ProviderProfile` this session is bound to. Never changes after
    /// creation without an explicit operator action.
    public let providerProfileId: UUID

    /// When set, the in-process MCP server scopes tool calls to this cluster
    /// unless the assistant explicitly names another.
    public let pinnedKubernetesContextId: ContextId?

    /// RFC 3339 timestamp when this session was created.
    public let createdAtRFC3339: String

    /// RFC 3339 timestamp of the most recent turn or metadata update.
    public let updatedAtRFC3339: String

    /// The system message that opens every turn. Editable per session.
    public let systemPrompt: String

    /// Current lifecycle status.
    public let status: SessionStatus

    /// Number of completed (user, assistant) turn pairs. Persisted for
    /// ordering and pruning; derived from message log.
    public let turnCount: Int

    public init(
        id: UUID = UUIDv7.generate(),
        title: String,
        providerProfileId: UUID,
        pinnedKubernetesContextId: ContextId? = nil,
        createdAtRFC3339: String,
        updatedAtRFC3339: String,
        systemPrompt: String = "",
        status: SessionStatus = .active,
        turnCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.providerProfileId = providerProfileId
        self.pinnedKubernetesContextId = pinnedKubernetesContextId
        self.createdAtRFC3339 = createdAtRFC3339
        self.updatedAtRFC3339 = updatedAtRFC3339
        self.systemPrompt = systemPrompt
        self.status = status
        self.turnCount = turnCount
    }
}
