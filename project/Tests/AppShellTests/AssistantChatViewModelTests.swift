// Tests/AppShellTests/AssistantChatViewModelTests.swift
// Coverage: AssistantChatViewModel session load + select + send flows.

import XCTest
import Dependencies
@testable import AppShell
import AssistantChat

// MARK: - AssistantChatViewModelTests

@MainActor
final class AssistantChatViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = AssistantChatViewModel()
        XCTAssertTrue(sut.sessions.isIdle)
        XCTAssertTrue(sut.messages.isIdle)
        XCTAssertNil(sut.currentSession)
        XCTAssertEqual(sut.draftInput, "")
    }

    // MARK: loadSessions

    func test_loadSessions_setsSessionsOnSuccess() async {
        let expected = [makeSession(title: "Alpha"), makeSession(title: "Beta")]
        let repo = FakeChatRepository(sessions: expected)

        await withDependencies {
            $0.chatRepository = repo
        } operation: {
            let sut = AssistantChatViewModel()
            await sut.loadSessions()
            XCTAssertEqual(sut.sessions.value?.map(\.title), ["Alpha", "Beta"])
        }
    }

    func test_loadSessions_setsFailureOnError() async {
        let repo = FakeChatRepository(sessionsError: ChatRepositoryError.unimplemented)

        await withDependencies {
            $0.chatRepository = repo
        } operation: {
            let sut = AssistantChatViewModel()
            await sut.loadSessions()
            XCTAssertNotNil(sut.sessions.error)
            XCTAssertNil(sut.sessions.value)
        }
    }

    // MARK: selectSession

    func test_selectSession_setsCurrentSessionAndLoadsMessages() async {
        let session = makeSession(title: "Gamma")
        let messages = [makeMessage(sessionId: session.id, role: .user, content: "Hello")]
        let repo = FakeChatRepository(sessions: [session], messages: messages)

        await withDependencies {
            $0.chatRepository = repo
        } operation: {
            let sut = AssistantChatViewModel()
            await sut.selectSession(session)
            XCTAssertEqual(sut.currentSession?.id, session.id)
            XCTAssertEqual(sut.messages.value?.count, 1)
        }
    }

    // MARK: sendMessage

    func test_sendMessage_clearsDraftAndAppendsMessage() async {
        let session = makeSession(title: "Delta")
        let repo = FakeChatRepository(sessions: [session])

        await withDependencies {
            $0.chatRepository = repo
        } operation: {
            let sut = AssistantChatViewModel()
            sut.currentSession = session
            await sut.sendMessage("kubectl get pods")
            XCTAssertEqual(sut.draftInput, "")
            XCTAssertEqual(repo.upsertedMessages.first?.content, "kubectl get pods")
        }
    }

    func test_sendMessage_noopsOnBlankInput() async {
        let session = makeSession(title: "Epsilon")
        let repo = FakeChatRepository(sessions: [session])

        await withDependencies {
            $0.chatRepository = repo
        } operation: {
            let sut = AssistantChatViewModel()
            sut.currentSession = session
            await sut.sendMessage("   ")
            XCTAssertTrue(repo.upsertedMessages.isEmpty)
        }
    }
}

// MARK: - Factory helpers

private func makeSession(title: String) -> ChatSession {
    ChatSession(
        title: title,
        providerProfileId: UUID(),
        createdAtRFC3339: "2026-01-01T00:00:00Z",
        updatedAtRFC3339: "2026-01-01T00:00:00Z"
    )
}

private func makeMessage(sessionId: UUID, role: MessageRole, content: String) -> ChatMessage {
    ChatMessage(
        sessionId: sessionId,
        turn: 0,
        createdAtRFC3339: "2026-01-01T00:00:00Z",
        role: role,
        content: content
    )
}

// MARK: - FakeChatRepository

private final class FakeChatRepository: ChatRepositoryPort, @unchecked Sendable {
    private let stubbedSessions: [ChatSession]
    private let stubbedMessages: [ChatMessage]
    private let sessionsError: Error?

    private(set) var upsertedMessages: [ChatMessage] = []

    init(
        sessions: [ChatSession] = [],
        messages: [ChatMessage] = [],
        sessionsError: Error? = nil
    ) {
        self.stubbedSessions = sessions
        self.stubbedMessages = messages
        self.sessionsError = sessionsError
    }

    func activeSessions() async throws -> [ChatSession] {
        if let error = sessionsError { throw error }
        return stubbedSessions
    }

    func messages(sessionId: UUID) async throws -> [ChatMessage] {
        stubbedMessages.filter { $0.sessionId == sessionId }
    }

    func upsert(message: ChatMessage) async throws {
        upsertedMessages.append(message)
    }

    func upsert(session: ChatSession) async throws {}
    func session(id: UUID) async throws -> ChatSession? { nil }
    func delete(sessionId: UUID) async throws {}
    func upsert(toolCallRecord: ToolCallRecord) async throws {}
    func toolCallRecords(parentMessageId: UUID) async throws -> [ToolCallRecord] { [] }
}
