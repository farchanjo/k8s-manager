// ViewModels/PortForwardListViewModel.swift — app_shell bounded context
// DDD role: ViewModel — Port-forward session list (Onda 3)
// ADR ref: ADR-0014 (lifecycle state machine), ADR-0034 (state-driven UI)

import Foundation
import AppKit
import Observation
import Dependencies
import Logging
import PortForwarding
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.port_forward_list")

// MARK: - ForwardStatus

/// UI projection of ``SessionStatus`` for the port-forward list table.
public enum ForwardStatus: String, Sendable, Equatable {
    case starting, active, degraded, reconnecting, stopped, failed

    /// SF Symbol name representing this status.
    public var symbolName: String {
        switch self {
        case .starting:     return "clock"
        case .active:       return "circle.fill"
        case .degraded:     return "exclamationmark.triangle"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .stopped:      return "stop.circle"
        case .failed:       return "xmark.circle"
        }
    }
}

// MARK: - PortForwardRow

/// Read-model projection of a ``PortForwardSession`` for the list table.
public struct PortForwardRow: Identifiable, Sendable, Hashable {
    /// Session UUID — stable across event updates.
    public let id: UUID
    /// Human-readable target name ("nginx-pod", "my-svc").
    public let targetName: String
    /// SF Symbol name: "cube.box" for pod, "network" for service.
    public let targetIcon: String
    public let localPort: Int
    public let remotePort: Int
    public let status: ForwardStatus
    public let bytesIn: Int
    public let bytesOut: Int
    /// Human-readable age (e.g. "5m", "2h").
    public let age: String
    /// URL string for open-in-browser and copy-URL actions.
    public let urlString: String

    public init(
        id: UUID,
        targetName: String,
        targetIcon: String,
        localPort: Int,
        remotePort: Int,
        status: ForwardStatus,
        bytesIn: Int,
        bytesOut: Int,
        age: String
    ) {
        self.id = id
        self.targetName = targetName
        self.targetIcon = targetIcon
        self.localPort = localPort
        self.remotePort = remotePort
        self.status = status
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.age = age
        self.urlString = "http://localhost:\(localPort)"
    }

    /// "1.2 MB ↓ / 845 KB ↑" formatted I/O counter.
    public var bytesFormatted: String {
        "\(Self.humanBytes(bytesIn)) ↓ / \(Self.humanBytes(bytesOut)) ↑"
    }

    private static func humanBytes(_ n: Int) -> String {
        switch n {
        case ..<1_024:           return "\(n) B"
        case ..<1_048_576:       return String(format: "%.1f KB", Double(n) / 1_024)
        case ..<1_073_741_824:   return String(format: "%.1f MB", Double(n) / 1_048_576)
        default:                 return String(format: "%.1f GB", Double(n) / 1_073_741_824)
        }
    }
}

// MARK: - PortForwardListViewModel

/// View model for the port-forward session list (Onda 3).
///
/// Subscribes to ``PortForwardEvent`` streams per session so ``ForwardStatus``
/// and byte counters update reactively. All mutations run on `MainActor`.
@MainActor @Observable
public final class PortForwardListViewModel {

    // MARK: Published state

    public var sessions: [PortForwardRow] = []
    public var selectedId: UUID?
    public var showingNewForwardSheet: Bool = false
    public var loadState: AsyncResource<Void> = .idle

    // MARK: Private state — event stream tasks keyed by session id

    @ObservationIgnored private var streamTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var bytesCounters: [UUID: (in: Int, out: Int)] = [:]
    @ObservationIgnored private var openedAtDates: [UUID: Date] = [:]

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.portForwardLifecycle) private var lifecyclePort

    @ObservationIgnored
    @Dependency(\.portForwardRepository) private var repo

    // Toast is passed via init (not a DependencyValues key — lives in AppShellDependencies).
    @ObservationIgnored private var toast: any ToastEmitterPort

    // MARK: Init

    public init(toast: any ToastEmitterPort = NoOpToastEmitter()) {
        self.toast = toast
    }

    // MARK: Public intents

    /// Loads persisted sessions for `clusterId` and subscribes to live events.
    public func start(clusterId: ClusterId) async {
        await reload()
    }

    /// Re-fetches sessions from the repository.
    public func reload() async {
        loadState = .loading
        do {
            let stored = try await repo.loadAll()
            sessions = stored.map(Self.project(_:))
            loadState = .success(())
            log.info("port-forward reload count=\(sessions.count)")
        } catch {
            loadState = .failure(error)
            log.error("port-forward reload failed — \(error)")
        }
    }

    /// Stops the session represented by `row` and removes it from the list.
    public func stop(_ row: PortForwardRow) async {
        await lifecyclePort.stop(sessionId: row.id)
        streamTasks[row.id]?.cancel()
        streamTasks[row.id] = nil
        sessions.removeAll { $0.id == row.id }
        await toast.emit(
            title: "Port forward stopped",
            message: "\(row.targetName) :\(row.localPort) → :\(row.remotePort)",
            severity: .info,
            iconSymbolName: "arrow.left.arrow.right",
            pinned: false,
            action: nil
        )
        log.info("stop id=\(row.id) name=\(row.targetName)")
    }

    /// Opens `http://localhost:<localPort>` in the default browser.
    public func openInBrowser(_ row: PortForwardRow) {
        guard let url = URL(string: row.urlString) else { return }
        NSWorkspace.shared.open(url)
        log.info("open-browser \(row.urlString)")
    }

    /// Copies the row URL to the system pasteboard.
    public func copyURL(_ row: PortForwardRow) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(row.urlString, forType: .string)
        log.info("copy-url \(row.urlString)")
    }

    // MARK: Stream subscription

    /// Subscribes to the event stream for a newly-started session.
    func subscribeToEvents(
        sessionId: UUID,
        stream: AsyncStream<PortForwardEvent>
    ) {
        streamTasks[sessionId]?.cancel()
        streamTasks[sessionId] = Task { [weak self] in
            guard let self else { return }
            for await event in stream {
                await self.handle(event)
            }
        }
    }

    // MARK: Private

    private func handle(_ event: PortForwardEvent) async {
        let id = event.sessionId
        switch event {
        case .sessionOpened:
            openedAtDates[id] = Date()
            updateStatus(id: id, status: .active)

        case .sessionFailed(let e):
            updateStatus(id: id, status: .failed)
            await toast.emit(
                title: "Port forward failed",
                message: e.detail,
                severity: .error,
                iconSymbolName: "xmark.circle",
                pinned: false,
                action: nil
            )

        case .sessionClosed:
            updateStatus(id: id, status: .stopped)

        case .bytesTransferred(let e):
            let prev = bytesCounters[id] ?? (in: 0, out: 0)
            bytesCounters[id] = (in: prev.in + e.bytesIn, out: prev.out + e.bytesOut)
            updateBytes(id: id)

        default:
            break
        }
    }

    private func updateStatus(id: UUID, status: ForwardStatus) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let row = sessions[idx]
        sessions[idx] = PortForwardRow(
            id: row.id, targetName: row.targetName, targetIcon: row.targetIcon,
            localPort: row.localPort, remotePort: row.remotePort, status: status,
            bytesIn: row.bytesIn, bytesOut: row.bytesOut, age: row.age
        )
    }

    private func updateBytes(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        let row = sessions[idx]
        let counters = bytesCounters[id] ?? (in: 0, out: 0)
        sessions[idx] = PortForwardRow(
            id: row.id, targetName: row.targetName, targetIcon: row.targetIcon,
            localPort: row.localPort, remotePort: row.remotePort, status: row.status,
            bytesIn: counters.in, bytesOut: counters.out, age: row.age
        )
    }

    private static func project(_ session: PortForwardSession) -> PortForwardRow {
        let targetName: String
        let targetIcon: String
        switch session.target {
        case .pod(let t):
            targetName = t.podName
            targetIcon = "cube.box"
        case .service(let t):
            targetName = t.serviceName
            targetIcon = "network"
        }
        let mapping = session.portMappings[0]
        return PortForwardRow(
            id: session.id,
            targetName: targetName,
            targetIcon: targetIcon,
            localPort: mapping.localPort,
            remotePort: mapping.remotePort,
            status: Self.status(from: session.status),
            bytesIn: 0, bytesOut: 0,
            age: Self.ageString(rfc3339: session.createdAtRFC3339)
        )
    }

    private static func status(from s: SessionStatus) -> ForwardStatus {
        switch s {
        case .opening:  return .starting
        case .running:  return .active
        case .closing:  return .stopped
        case .closed:   return .stopped
        case .error:    return .failed
        }
    }

    private static func ageString(rfc3339: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: rfc3339) else { return "—" }
        let sec = Int(-date.timeIntervalSinceNow)
        switch sec {
        case ..<60:    return "\(sec)s"
        case ..<3600:  return "\(sec / 60)m"
        case ..<86400: return "\(sec / 3600)h"
        default:       return "\(sec / 86400)d"
        }
    }
}
