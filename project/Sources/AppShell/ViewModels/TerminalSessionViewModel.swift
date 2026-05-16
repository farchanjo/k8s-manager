// ViewModels/TerminalSessionViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0017 (terminal_session)

import Foundation
import Dependencies
import Logging
import TerminalSession
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.terminal_session")

// MARK: - TerminalSessionViewModel

/// View model for the terminal session screen.
///
/// Owned by `TerminalSessionView`. Drives session listing, session opening,
/// input forwarding, and cooperative close. All mutations happen on the
/// `MainActor` so SwiftUI observation coalesces updates without data races.
@Observable
@MainActor
public final class TerminalSessionViewModel {

    // MARK: State

    /// Lifecycle state of the session list load operation.
    public var sessions: AsyncResource<[TerminalSession]> = .idle

    /// Accumulated stdout/stderr text for the active session.
    public var outputBuffer: String = ""

    /// The session currently selected in the list, if any.
    public var activeSessionId: UUID?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.podExec) private var podExec

    @ObservationIgnored
    @Dependency(\.nodeDebug) private var nodeDebug

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads (or refreshes) the list of known terminal sessions.
    ///
    /// Ports are not yet wired — reports an empty success so the view shows
    /// empty-state rather than a hard error (ADR-0031).
    public func loadSessions() async {
        sessions = .loading
        log.info("loadSessions start")
        sessions = .success([])
        log.info("loadSessions OK — sessions=0 (no adapter wired)")
    }

    /// Opens a new terminal session for the given target and kind.
    ///
    /// - Parameters:
    ///   - target: The Kubernetes resource to attach to.
    ///   - kind: Whether this is a pod exec or node debug session.
    public func openSession(target: SessionTarget, kind: SessionKind) async {
        log.info("openSession kind=\(kind.rawValue)")
        do {
            switch kind {
            case .podExec:
                try await openPodExecSession(target: target)
            case .nodeDebug:
                try await openNodeDebugSession(target: target)
            }
        } catch {
            log.error("openSession FAILED — \(error)")
            sessions = .failure(error)
        }
    }

    /// Appends raw input text to the active session's stdin.
    ///
    /// No-op when no session is active or the adapter is unwired.
    ///
    /// - Parameter text: UTF-8 string to forward as stdin bytes.
    public func sendInput(_ text: String) {
        guard let id = activeSessionId else {
            log.warning("sendInput ignored — no active session")
            return
        }
        guard let data = text.data(using: .utf8) else { return }
        log.info("sendInput sessionId=\(id) bytes=\(data.count)")
        outputBuffer += text
    }

    /// Cooperatively closes the identified session.
    ///
    /// Marks the session `.closed` in the list and appends a status line to
    /// the output buffer. Actual WebSocket teardown is delegated to the adapter
    /// when wired.
    ///
    /// - Parameter sessionId: UUID of the session to close.
    public func closeSession(_ sessionId: UUID) async {
        log.info("closeSession sessionId=\(sessionId)")
        if activeSessionId == sessionId {
            activeSessionId = nil
        }
        if case .success(let list) = sessions {
            let updated = list.map { s -> TerminalSession in
                s.id == sessionId ? s.withStatus(.closed) : s
            }
            sessions = .success(updated)
        }
        outputBuffer += "\n[Session \(sessionId) closed]\n"
    }

    // MARK: Private helpers

    private func openPodExecSession(target: SessionTarget) async throws {
        guard case .pod(let podTarget) = target else { return }
        let request = PodExecRequest(
            namespace: podTarget.namespace,
            podName: podTarget.podName,
            containerName: podTarget.containerName,
            command: ["/bin/sh"],
            tty: true,
            stdin: true
        )
        let connection = try await podExec.openExec(request: request)
        let session = makeSession(kind: .podExec, target: target, subprotocol: connection.subprotocol)
        appendSession(session)
        activeSessionId = session.id
        log.info("openPodExecSession OK — sessionId=\(session.id) subprotocol=\(connection.subprotocol.rawValue)")
    }

    private func openNodeDebugSession(target: SessionTarget) async throws {
        guard case .node(let nodeTarget) = target else { return }
        let now = iso8601Now()
        let expiry = iso8601Offset(seconds: 3660, from: now)
        let descriptor = NodeDebugDescriptor.make(
            nodeName: nodeTarget.nodeName,
            debugImage: nodeTarget.debugImage,
            expiresAt: expiry
        )
        let podName = try await nodeDebug.createDebugPod(descriptor: descriptor)
        let session = makeSession(kind: .nodeDebug, target: target, subprotocol: nil)
        appendSession(session)
        activeSessionId = session.id
        log.info("openNodeDebugSession OK — sessionId=\(session.id) ephemeralPod=\(podName)")
    }

    private func makeSession(
        kind: SessionKind,
        target: SessionTarget,
        subprotocol: ExecSubprotocol?
    ) -> TerminalSession {
        let now = iso8601Now()
        return TerminalSession(
            kind: kind,
            kubernetesContextId: UUIDv7.generate(),
            targetRef: target,
            command: ["/bin/sh"],
            tty: true,
            stdin: true,
            createdAt: now,
            lastActivityAt: now,
            subprotocol: subprotocol
        )
    }

    private func appendSession(_ session: TerminalSession) {
        if case .success(let list) = sessions {
            sessions = .success(list + [session])
        } else {
            sessions = .success([session])
        }
    }

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private func iso8601Offset(seconds: TimeInterval, from base: String) -> String {
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: base) ?? Date()
        return formatter.string(from: date.addingTimeInterval(seconds))
    }
}
