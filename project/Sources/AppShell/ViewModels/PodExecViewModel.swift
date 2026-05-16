// ViewModels/PodExecViewModel.swift — app_shell bounded context
// DDD role: ViewModel — pod exec terminal tab
// ADR ref: ADR-0017 (terminal sessions), ADR-0034 (state-driven UI)

import Foundation
import Observation
import Dependencies
import Logging
import TerminalSession
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.pod_exec")

// MARK: - ExecConnectionState

/// Observable lifecycle state for an exec tab.
public enum ExecConnectionState: Sendable, Equatable {
    /// Initial WebSocket handshake in progress.
    case connecting
    /// WebSocket open; receive loop running.
    case connected
    /// Attempting to re-open after an unexpected closure.
    case reconnecting
    /// Session closed; optional human-readable reason.
    case disconnected(reason: String?)
    /// Unrecoverable error; human-readable description.
    case failed(error: String)
}

// MARK: - PodExecViewModel

/// View model owned by `PodExecTab`.
///
/// Manages the `TerminalSessionActor` lifecycle, accumulates output into a
/// 64 KB ring buffer, and forwards keyboard input to the exec channel.
/// All published state mutations happen on `@MainActor` so SwiftUI observation
/// coalesces updates without data races.
@Observable
@MainActor
public final class PodExecViewModel {

    // MARK: Published state

    /// Accumulated stdout + stderr as a string. Capped at 64 KB; oldest 16 KB
    /// dropped when the cap is exceeded (ring-buffer semantics).
    public var outputBuffer: String = ""

    /// Current WebSocket lifecycle state displayed in the toolbar.
    public var connectionState: ExecConnectionState = .connecting

    /// The container name the session is currently attached to.
    public var selectedContainer: String?

    /// Containers available for the pod (populated via list port).
    public var availableContainers: [String] = []

    /// Current terminal width in columns.
    public var terminalCols: Int = 80

    /// Current terminal height in rows.
    public var terminalRows: Int = 24

    // MARK: Private state

    @ObservationIgnored private var sessionActor: TerminalSessionActor?
    @ObservationIgnored private var outputTask: Task<Void, Never>?
    @ObservationIgnored private var clusterId: ClusterId?
    @ObservationIgnored private var podRef: ResourceRef?
    @ObservationIgnored private var requestedContainer: String?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.podExec) private var execPort

    // MARK: Init

    public init() {}

    // MARK: Public intents

    /// Opens the exec connection for the given pod. Called from `.task` in the view.
    public func connect(
        clusterId: ClusterId,
        podRef: ResourceRef,
        container: String?
    ) async {
        self.clusterId = clusterId
        self.podRef = podRef
        self.requestedContainer = container
        self.selectedContainer = container ?? podRef.name
        connectionState = .connecting
        await openSession(container: container, podRef: podRef)
    }

    /// Forwards raw keyboard input to the remote process stdin (channel 0).
    public func sendInput(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let actor = sessionActor
        outputTask?.cancel()
        outputTask = Task {
            try? await actor?.sendInput(data)
        }
    }

    /// Reports a terminal resize from the view. Debounced inside the actor.
    public func resizeTerminal(cols: Int, rows: Int) {
        guard cols >= 1, rows >= 1 else { return }
        terminalCols = cols
        terminalRows = rows
        let actor = sessionActor
        Task {
            let size = TerminalSize(rows: rows, cols: cols)
            try? await actor?.sendResize(size)
        }
    }

    /// Reconnects after a disconnect. Resets output buffer.
    public func reconnect() async {
        guard let ref = podRef else { return }
        outputBuffer = ""
        connectionState = .reconnecting
        await openSession(container: requestedContainer, podRef: ref)
    }

    /// Switches to a different container in the same pod.
    public func switchContainer(_ name: String) async {
        guard let ref = podRef else { return }
        await sessionActor?.close()
        sessionActor = nil
        outputBuffer = ""
        selectedContainer = name
        requestedContainer = name
        connectionState = .connecting
        await openSession(container: name, podRef: ref)
    }

    /// Cooperatively closes the session.
    public func disconnect() async {
        outputTask?.cancel()
        await sessionActor?.close()
        sessionActor = nil
        connectionState = .disconnected(reason: "Closed by user")
    }

    /// No-op close stub called by the tab close button.
    public func close() {
        Task { await disconnect() }
    }

    // MARK: Private helpers

    private func openSession(container: String?, podRef: ResourceRef) async {
        let ns = podRef.namespace ?? "default"
        let request = PodExecRequest(
            namespace: ns,
            podName: podRef.name,
            containerName: container,
            command: ["/bin/sh"],
            tty: true,
            stdin: true
        )
        do {
            let connection = try await execPort.openExec(request: request)
            let now = iso8601Now()
            let session = TerminalSession(
                kind: .podExec,
                kubernetesContextId: UUIDv7.generate(),
                targetRef: .pod(PodTarget(
                    namespace: ns,
                    podName: podRef.name,
                    containerName: container
                )),
                command: ["/bin/sh"],
                tty: true,
                stdin: true,
                createdAt: now,
                lastActivityAt: now,
                subprotocol: connection.subprotocol
            )
            let actor = TerminalSessionActor(session: session)
            sessionActor = actor
            connectionState = .connected
            try await actor.open()
            startOutputLoop(actor: actor)
        } catch {
            log.error("openSession failed — \(error)")
            connectionState = .failed(error: error.localizedDescription)
        }
    }

    private func startOutputLoop(actor: TerminalSessionActor) {
        outputTask?.cancel()
        outputTask = Task<Void, Never> { [weak self] in
            let stream = await actor.outputStream()
            do {
                for try await frame in stream {
                    guard let self else { break }
                    self.appendFrame(frame)
                }
            } catch {
                // Stream finished with error — connection dropped.
            }
            if let self, case .connected = self.connectionState {
                self.connectionState = .disconnected(reason: nil)
            }
        }
    }

    private func appendFrame(_ frame: TerminalIOFrame) {
        let bytes: Data?
        switch frame {
        case .stdout(let f): bytes = f.bytes
        case .stderr(let f): bytes = f.bytes
        case .error(let f):
            let msg = "\r\n[Error: \(f.json)]\r\n"
            appendOutput(msg.data(using: .utf8) ?? Data())
            return
        default: return
        }
        if let b = bytes { appendOutput(b) }
    }

    /// Appends decoded bytes to `outputBuffer`; enforces 64 KB ring cap.
    private func appendOutput(_ data: Data) {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        outputBuffer += text
        let maxBytes = 64 * 1024
        let dropBytes = 16 * 1024
        if outputBuffer.utf8.count > maxBytes {
            let utf8 = outputBuffer.utf8
            let dropIndex = utf8.index(utf8.startIndex, offsetBy: dropBytes)
            outputBuffer = String(outputBuffer[dropIndex...])
        }
    }

    private func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
