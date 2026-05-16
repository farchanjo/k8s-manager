// ViewModels/NodeDebugViewModel.swift — app_shell bounded context
// DDD role: ViewModel — node debug terminal tab
// ADR ref: ADR-0017 (terminal sessions), ADR-0012 (mutating ops)

import Foundation
import Observation
import Dependencies
import Logging
import TerminalSession
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.node_debug")

// MARK: - NodeDebugViewModel

/// View model owned by `NodeDebugTab`.
///
/// Creates an ephemeral debug Pod on the target node via `NodeDebugPort`,
/// waits for it to reach `Running`, then opens an exec connection into it.
/// On disconnect the ephemeral Pod is deleted cooperatively.
///
/// All published state mutations happen on `@MainActor`.
@Observable
@MainActor
public final class NodeDebugViewModel {

    // MARK: Published state

    /// Accumulated stdout + stderr. 64 KB ring buffer; 16 KB oldest dropped.
    public var outputBuffer: String = ""

    /// Current WebSocket lifecycle state.
    public var connectionState: ExecConnectionState = .connecting

    /// Name of the ephemeral debug Pod currently running, or `nil` before creation.
    public var ephemeralPodName: String?

    /// Terminal width in columns.
    public var terminalCols: Int = 80

    /// Terminal height in rows.
    public var terminalRows: Int = 24

    // MARK: Private state

    @ObservationIgnored private var sessionActor: TerminalSessionActor?
    @ObservationIgnored private var outputTask: Task<Void, Never>?
    @ObservationIgnored private var descriptor: NodeDebugDescriptor?
    @ObservationIgnored private var clusterId: ClusterId?
    @ObservationIgnored private var nodeRef: ResourceRef?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.podExec) private var execPort

    @ObservationIgnored
    @Dependency(\.nodeDebug) private var debugPort

    // MARK: Init

    public init() {}

    // MARK: Public intents

    /// Creates the debug pod, waits for it to be running, then opens exec.
    public func connect(clusterId: ClusterId, nodeRef: ResourceRef) async {
        self.clusterId = clusterId
        self.nodeRef = nodeRef
        connectionState = .connecting
        await openDebugSession(nodeRef: nodeRef)
    }

    /// Forwards keyboard input to the remote process stdin.
    public func sendInput(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        let actor = sessionActor
        Task { try? await actor?.sendInput(data) }
    }

    /// Reports a terminal resize from the view.
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

    /// Reconnects by creating a fresh debug pod.
    public func reconnect() async {
        guard let ref = nodeRef else { return }
        await cleanupPod()
        outputBuffer = ""
        connectionState = .reconnecting
        await openDebugSession(nodeRef: ref)
    }

    /// Cooperatively closes the session and deletes the ephemeral Pod.
    public func disconnect() async {
        outputTask?.cancel()
        await sessionActor?.close()
        sessionActor = nil
        await cleanupPod()
        connectionState = .disconnected(reason: "Closed by user")
    }

    /// Sync close stub called by the tab close button.
    public func close() {
        Task { await disconnect() }
    }

    // MARK: Private helpers

    private func openDebugSession(nodeRef: ResourceRef) async {
        let now = iso8601Now()
        let expiry = iso8601Offset(seconds: 3660, from: now)
        let desc = NodeDebugDescriptor.make(nodeName: nodeRef.name, expiresAt: expiry)
        descriptor = desc

        do {
            let podName = try await debugPort.createDebugPod(descriptor: desc)
            ephemeralPodName = podName
            log.info("debug pod created pod=\(podName)")
            let request = PodExecRequest(
                namespace: desc.namespace,
                podName: podName,
                containerName: nil,
                command: ["/bin/bash"],
                tty: true,
                stdin: true
            )
            let connection = try await execPort.openExec(request: request)
            let session = TerminalSession(
                kind: .nodeDebug,
                kubernetesContextId: UUIDv7.generate(),
                targetRef: .node(NodeTarget(
                    nodeName: nodeRef.name,
                    debugContainerName: podName
                )),
                command: ["/bin/bash"],
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
            log.error("openDebugSession failed — \(error)")
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

    private func cleanupPod() async {
        guard let desc = descriptor else { return }
        do {
            try await debugPort.deleteDebugPod(
                podName: desc.ephemeralPodName,
                namespace: desc.namespace
            )
            log.info("debug pod deleted pod=\(desc.ephemeralPodName)")
        } catch {
            log.warning("debug pod delete failed (may already be gone) — \(error)")
        }
        descriptor = nil
        ephemeralPodName = nil
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
