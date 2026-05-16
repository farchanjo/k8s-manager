// ViewModels/AssistantChatViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import Foundation
import Dependencies
import Logging
import AssistantChat
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.assistant_chat")

// MARK: - AssistantChatViewModel

/// View model for the assistant chat screen.
///
/// Owned by `AssistantChatView`. Drives session listing, session selection,
/// message loading, and outbound message dispatch. All mutations happen on
/// `MainActor` so SwiftUI observation coalesces updates without data races.
@Observable
@MainActor
public final class AssistantChatViewModel {

    // MARK: State

    /// Lifecycle state of the active-sessions fetch operation.
    public var sessions: AsyncResource<[ChatSession]> = .idle

    /// The currently selected session, if any.
    public var currentSession: ChatSession?

    /// Messages for the currently selected session.
    public var messages: AsyncResource<[ChatMessage]> = .idle

    /// Text typed by the user in the input field, not yet sent.
    public var draftInput: String = ""

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.chatRepository) private var chatRepository

    @ObservationIgnored
    @Dependency(\.toolDispatcher) private var toolDispatcher

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Fetches all active sessions from the repository.
    public func loadSessions() async {
        sessions = .loading
        log.info("loadSessions start")
        do {
            let list = try await chatRepository.activeSessions()
            log.info("loadSessions OK — count=\(list.count)")
            sessions = .success(list)
        } catch {
            log.error("loadSessions FAILED — \(error)")
            sessions = .failure(error)
        }
    }

    /// Makes `session` the active session and loads its messages.
    ///
    /// - Parameter session: The session the user tapped in the sidebar.
    public func selectSession(_ session: ChatSession) async {
        currentSession = session
        log.info("selectSession id=\(session.id) title=\(session.title)")
        await loadMessages(for: session)
    }

    /// Sends `text` as a user message in the current session.
    ///
    /// No-ops when no session is selected or the draft is blank.
    ///
    /// - Parameter text: The user-supplied text to send.
    public func sendMessage(_ text: String) async {
        guard let session = currentSession, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        draftInput = ""
        let turn = messages.value?.count ?? 0
        let userMessage = ChatMessage(
            sessionId: session.id,
            turn: turn,
            createdAtRFC3339: ISO8601DateFormatter().string(from: Date()),
            role: .user,
            content: text
        )
        log.info("sendMessage sessionId=\(session.id) turn=\(turn)")
        do {
            try await chatRepository.upsert(message: userMessage)
            await loadMessages(for: session)
        } catch {
            log.error("sendMessage upsert FAILED — \(error)")
        }
    }

    // MARK: Private helpers

    private func loadMessages(for session: ChatSession) async {
        messages = .loading
        do {
            let list = try await chatRepository.messages(sessionId: session.id)
            log.info("loadMessages OK — sessionId=\(session.id) count=\(list.count)")
            messages = .success(list)
        } catch {
            log.error("loadMessages FAILED — \(error)")
            messages = .failure(error)
        }
    }
}
