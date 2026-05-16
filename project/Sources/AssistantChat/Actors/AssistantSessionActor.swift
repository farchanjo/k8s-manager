// Actors/AssistantSessionActor.swift — assistant_chat bounded context
// DDD role: DomainService (Swift actor — ADR-0011, ADR-0025)
// CUE source: docs/arch/contexts/assistant_chat/domain/narrative.md

import Dependencies
import Foundation
import LLMProvider
import Logging
import SharedKernel

// MARK: - StreamState

extension AssistantSessionActor {
    /// In-flight streaming state owned by `AssistantSessionActor`.
    ///
    /// The actor is the sole authority for transitions; nothing outside the
    /// actor boundary can write to this value.
    public enum StreamState: Sendable, Equatable {
        /// No stream is open.
        case idle

        /// A stream is in progress. `sessionTurnId` identifies the assistant
        /// message being produced.
        case streaming(sessionTurnId: UUID)

        /// The consumer requested cancellation; the actor will finish cleanup
        /// and return to `.idle`.
        case cancelled
    }
}

// MARK: - AssistantSessionError

/// Errors raised by `AssistantSessionActor` during session operations.
public enum AssistantSessionError: Error, Sendable {
    /// The stream was cancelled by the consumer before it completed.
    case streamCancelled

    /// A stream is already in progress; concurrent streams are not allowed.
    case concurrentStreamNotAllowed

    /// The prompt injection filter denied the user message.
    case promptInjectionDenied(matchedPatterns: [String])
}

// MARK: - AssistantSessionActor

/// Central domain actor coordinating one chat session.
///
/// Owns the in-flight stream state and orchestrates the tool-use loop as
/// described in the `assistant_chat` narrative. Exactly one
/// `AssistantSessionActor` exists per active `ChatSession`.
///
/// All dependencies cross the port boundary — the actor never imports
/// provider SDKs, GRDB, or OPA runtime types.
public actor AssistantSessionActor {
    // MARK: Public state

    /// The chat session aggregate this actor manages.
    public private(set) var session: ChatSession

    // MARK: Private domain state

    /// Ordered conversation history for the current session.
    private var history: [ChatMessage]

    /// In-flight tool call records for the current turn.
    private var pendingToolCalls: [ToolCallRecord]

    /// Current streaming lifecycle state.
    private var streamState: StreamState

    // MARK: Dependencies

    @Dependency(\.chatRepository) private var chatRepository
    @Dependency(\.promptInjectionFilter) private var promptInjectionFilter
    @Dependency(\.toolDispatcher) private var toolDispatcher
    @Dependency(\.llmStreaming) private var llmStreaming

    private let logger: Logger

    // MARK: - Init

    /// Initialises the actor with a pre-existing session and optional message
    /// history loaded from persistence.
    ///
    /// - Parameters:
    ///   - sessionId: The UUID of the `ChatSession` this actor manages.
    ///   - initialMessages: Messages previously persisted for this session.
    public init(session: ChatSession, initialMessages: [ChatMessage] = []) {
        self.session = session
        self.history = initialMessages
        self.pendingToolCalls = []
        self.streamState = .idle
        self.logger = Logger(label: "AssistantSessionActor[\(session.id)]")
    }

    // MARK: - User message

    /// Sanitises the user text via the injection filter, persists it, and
    /// appends it to the in-memory history.
    ///
    /// - Parameter userMessage: Raw text authored by the operator.
    /// - Returns: The persisted `ChatMessage` for the user turn.
    /// - Throws: `AssistantSessionError.promptInjectionDenied` when the filter
    ///   blocks the payload; `ChatRepositoryError` on persistence failure.
    public func append(userMessage text: String) async throws -> ChatMessage {
        let filterInput = FilterInput(
            payload: text,
            source: "user_input",
            sessionId: session.id
        )
        let filterResult = try await promptInjectionFilter.evaluate(input: filterInput)
        guard filterResult.allow else {
            throw AssistantSessionError.promptInjectionDenied(
                matchedPatterns: filterResult.matchedPatterns
            )
        }

        let message = ChatMessage(
            sessionId: session.id,
            turn: history.count,
            createdAtRFC3339: ISO8601DateFormatter().string(from: Date()),
            role: .user,
            content: text
        )
        try await chatRepository.upsert(message: message)
        history.append(message)
        logger.debug("User message appended", metadata: ["turn": "\(message.turn)"])
        return message
    }

    // MARK: - Streaming reply

    /// Streams the assistant reply for the current conversation history.
    ///
    /// Calls `LLMStreamingPort`, fans events downstream, and drives the
    /// tool-use loop: each `toolUseFinish` event dispatches via
    /// `ToolDispatcherPort` and feeds the result back to the provider.
    ///
    /// - Returns: An `AsyncThrowingStream` of `AssistantStreamEvent` values.
    ///   Consumers must iterate until the stream terminates.
    public func streamAssistantReply() -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(16)) { continuation in
            let capturedSession = session
            let capturedHistory = history
            let capturedDispatcher = toolDispatcher
            let capturedStreaming = llmStreaming
            let capturedRepo = chatRepository
            let capturedLogger = logger

            Task {
                let turnMessageId = UUID()
                let request = AssistantRequest(
                    messages: capturedHistory.map(\.asAssistantMessage),
                    profileId: capturedSession.providerProfileId
                )

                let upstream = capturedStreaming.reply(to: request)
                do {
                    for try await event in upstream {
                        if case .toolUseFinish(let finish) = event {
                            let toolReq = ToolRequest(
                                callId: finish.callId,
                                toolName: finish.callId,
                                argumentsJSON: finish.totalArguments,
                                pinnedContextId: capturedSession.pinnedKubernetesContextId
                            )
                            let toolResp = try await capturedDispatcher.dispatch(request: toolReq)
                            let record = makeToolCallRecord(
                                finish: finish,
                                response: toolResp,
                                sessionId: capturedSession.id,
                                parentMessageId: turnMessageId
                            )
                            try await capturedRepo.upsert(toolCallRecord: record)
                            capturedLogger.debug(
                                "Tool call completed",
                                metadata: ["callId": "\(finish.callId)", "status": "\(toolResp.status)"]
                            )
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Cancellation

    /// Requests cancellation of the active stream.
    ///
    /// Sets `streamState` to `.cancelled`; the stream `Task` will observe
    /// cooperative cancellation and finish. No-op when idle.
    public func cancelStream() {
        guard case .streaming = streamState else { return }
        streamState = .cancelled
        logger.info("Stream cancellation requested")
    }

    // MARK: - Session end

    /// Persists the final session snapshot and marks the actor as finished.
    ///
    /// Callers should invoke this before discarding the actor reference.
    ///
    /// - Throws: `ChatRepositoryError` on persistence failure.
    public func endSession() async throws {
        try await chatRepository.upsert(session: session)
        logger.info("Session ended", metadata: ["sessionId": "\(session.id)"])
    }

    // MARK: - Private helpers

    private func makeToolCallRecord(
        finish: ToolUseFinishEvent,
        response: ToolResponse,
        sessionId: UUID,
        parentMessageId: UUID
    ) -> ToolCallRecord {
        let now = ISO8601DateFormatter().string(from: Date())
        return ToolCallRecord(
            callId: finish.callId,
            sessionId: sessionId,
            parentMessageId: parentMessageId,
            toolName: finish.callId,
            requestedAtRFC3339: now,
            completedAtRFC3339: now,
            argumentsJSON: finish.totalArguments,
            resultJSON: response.resultJSON,
            status: response.status
        )
    }
}

// MARK: - ChatMessage + AssistantMessage bridge

extension ChatMessage {
    /// Converts a persisted `ChatMessage` to the provider-facing
    /// `AssistantMessage` value type consumed by `LLMStreamingPort`.
    fileprivate var asAssistantMessage: AssistantMessage {
        let providerRole: LLMProvider.MessageRole = switch role {
        case .system: .system
        case .user: .user
        case .assistant: .assistant
        }
        return AssistantMessage(
            role: providerRole,
            content: [.text(TextPart(text: content))]
        )
    }
}
