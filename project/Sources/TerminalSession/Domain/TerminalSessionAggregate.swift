// Domain/TerminalSession.swift — terminal_session bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/terminal_session/schemas/terminal_session.cue
// ADR ref: ADR-0017

import Foundation
import SharedKernel

// MARK: - SessionKind

/// Discriminator between the two session modes supported by this bounded context.
///
/// Mirrors the `kind` field in `#TerminalSession`.
public enum SessionKind: String, Hashable, Sendable, Codable {
    /// An interactive exec session into a container inside a Pod.
    case podExec = "pod_exec"
    /// A privileged debug session on a Node's host namespace (ephemeral Pod created).
    case nodeDebug = "node_debug"
}

// MARK: - SessionStatus

/// Lifecycle state of a `TerminalSession` aggregate.
///
/// Legal transitions per ADR-0017 state machine:
/// ```
/// opening → open → closing → closed
/// opening → error
/// open    → error
/// ```
public enum SessionStatus: String, Hashable, Sendable, Codable {
    /// WebSocket handshake in progress; Pod creation running for node debug sessions.
    case opening
    /// WebSocket connected; receive loop running; resize and stdin accepted.
    case open
    /// Cooperative cancel dispatched; awaiting WebSocket close frame or 200 ms timeout.
    case closing
    /// Connection terminated cleanly; exit code captured when available.
    case closed
    /// Connection failed or reset unexpectedly.
    case error
}

// MARK: - PodTarget

/// Describes the Kubernetes Pod and container that a `podExec` session is attached to.
///
/// Mirrors `#PodTarget` in `terminal_session.cue`. Value object — immutable after
/// construction.
public struct PodTarget: Hashable, Sendable, Codable {
    /// Kubernetes namespace of the target Pod.
    public let namespace: String
    /// Name of the target Pod.
    public let podName: String
    /// Regular container name to exec into. When `nil`, the adapter defaults to
    /// the first container in the Pod spec (matches `kubectl exec` behaviour).
    public let containerName: String?
    /// Ephemeral debug container name. Mutually exclusive with `containerName`.
    public let ephemeralContainerName: String?

    public init(
        namespace: String,
        podName: String,
        containerName: String? = nil,
        ephemeralContainerName: String? = nil
    ) {
        self.namespace = namespace
        self.podName = podName
        self.containerName = containerName
        self.ephemeralContainerName = ephemeralContainerName
    }
}

// MARK: - NodeTarget

/// Describes the Kubernetes Node and the ephemeral debug Pod created by K8sManager.
///
/// Mirrors `#NodeTarget` in `terminal_session.cue`. Value object — immutable after
/// construction.
public struct NodeTarget: Hashable, Sendable, Codable {
    /// Name of the target Kubernetes node.
    public let nodeName: String
    /// Container image used for the ephemeral debug Pod.
    /// Default: `"nicolaka/netshoot:v0.13"` per ADR-0017.
    public let debugImage: String
    /// Name assigned to the debug container inside the ephemeral Pod.
    public let debugContainerName: String

    public init(
        nodeName: String,
        debugImage: String = "nicolaka/netshoot:v0.13",
        debugContainerName: String
    ) {
        self.nodeName = nodeName
        self.debugImage = debugImage
        self.debugContainerName = debugContainerName
    }
}

// MARK: - SessionTarget

/// Discriminated union of the two target reference types.
///
/// Enforces the invariant: `podExec` sessions carry `#PodTarget`;
/// `nodeDebug` sessions carry `#NodeTarget`.
public enum SessionTarget: Hashable, Sendable {
    case pod(PodTarget)
    case node(NodeTarget)
}

extension SessionTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, pod, node
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try container.decode(String.self, forKey: .type)
        switch type_ {
        case "pod":
            self = .pod(try container.decode(PodTarget.self, forKey: .pod))
        case "node":
            self = .node(try container.decode(NodeTarget.self, forKey: .node))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown SessionTarget type: \(type_)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pod(let t):
            try container.encode("pod", forKey: .type)
            try container.encode(t, forKey: .pod)
        case .node(let t):
            try container.encode("node", forKey: .type)
            try container.encode(t, forKey: .node)
        }
    }
}

// MARK: - ExecSubprotocol

/// Kubernetes WebSocket exec subprotocol variant negotiated at session open.
///
/// Per ADR-0017: the application requests `v5` and falls back to `v4` when the
/// server downgrades. v5 introduces the dedicated error channel (channel 3);
/// v4 embeds error information in the stderr stream.
public enum ExecSubprotocol: String, Hashable, Sendable, Codable {
    /// `v5.channel.k8s.io` — preferred; Kubernetes 1.31+.
    case v5 = "v5.channel.k8s.io"
    /// `v4.channel.k8s.io` — fallback; clusters older than 1.31.
    case v4 = "v4.channel.k8s.io"
}

// MARK: - TerminalSession

/// Aggregate root for a single interactive terminal session.
///
/// Represents either a `pods/exec` connection (`podExec`) or a `nodes/debug`
/// connection (`nodeDebug`). Owned and written exclusively by one
/// `TerminalSessionActor` per ADR-0011 / ADR-0017.
///
/// Invariants:
/// - `sizeRows >= 1`, `sizeCols >= 1`.
/// - `exitCode` is present only when `status` is `.closed` or `.error`.
/// - `targetRef` matches `kind`: `.podExec` → `.pod(_)`, `.nodeDebug` → `.node(_)`.
/// - `lastActivityAt >= createdAt`.
public struct TerminalSession: Hashable, Sendable, Codable {
    /// UUIDv7 that uniquely identifies this session. Embeds a millisecond-precision
    /// timestamp for natural chronological ordering.
    public let id: UUID

    /// Discriminates between pod exec and node debug sessions.
    public let kind: SessionKind

    /// UUIDv7 of the active kubeconfig context under which this session was opened.
    /// Assigned by the `cluster_connectivity` context.
    public let kubernetesContextId: UUID

    /// Target resource this session is attached to.
    public let targetRef: SessionTarget

    /// `argv` list passed to the exec endpoint. Must be non-empty.
    public let command: [String]

    /// Whether the remote process was started with a pseudo-terminal allocated.
    public let tty: Bool

    /// Whether the stdin stream is forwarded.
    public let stdin: Bool

    /// RFC 3339 timestamp when the session aggregate was created.
    public let createdAt: String

    /// RFC 3339 timestamp updated on every inbound or outbound frame.
    /// Used by the idle-timeout check loop (threshold: 30 min).
    public let lastActivityAt: String

    /// Current lifecycle state.
    public let status: SessionStatus

    /// Process exit code from channel 3 (`v5.channel.k8s.io`).
    /// Present only when `status` is `.closed` or `.error` and the remote process
    /// exited with an explicit code.
    public let exitCode: Int?

    /// Current terminal height in character rows. Must be >= 1.
    public let sizeRows: Int

    /// Current terminal width in character columns. Must be >= 1.
    public let sizeCols: Int

    /// Subprotocol negotiated at session open. `nil` before the handshake completes.
    public let subprotocol: ExecSubprotocol?

    public init(
        id: UUID = UUIDv7.generate(),
        kind: SessionKind,
        kubernetesContextId: UUID,
        targetRef: SessionTarget,
        command: [String],
        tty: Bool,
        stdin: Bool,
        createdAt: String,
        lastActivityAt: String,
        status: SessionStatus = .opening,
        exitCode: Int? = nil,
        sizeRows: Int = 24,
        sizeCols: Int = 80,
        subprotocol: ExecSubprotocol? = nil
    ) {
        precondition(!command.isEmpty, "command must be non-empty")
        precondition(sizeRows >= 1, "sizeRows must be >= 1")
        precondition(sizeCols >= 1, "sizeCols must be >= 1")
        self.id = id
        self.kind = kind
        self.kubernetesContextId = kubernetesContextId
        self.targetRef = targetRef
        self.command = command
        self.tty = tty
        self.stdin = stdin
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.status = status
        self.exitCode = exitCode
        self.sizeRows = sizeRows
        self.sizeCols = sizeCols
        self.subprotocol = subprotocol
    }

    /// Returns a copy with the given `status`, optionally capturing an `exitCode`.
    public func withStatus(_ newStatus: SessionStatus, exitCode: Int? = nil) -> Self {
        Self(
            id: id,
            kind: kind,
            kubernetesContextId: kubernetesContextId,
            targetRef: targetRef,
            command: command,
            tty: tty,
            stdin: stdin,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            status: newStatus,
            exitCode: exitCode ?? self.exitCode,
            sizeRows: sizeRows,
            sizeCols: sizeCols,
            subprotocol: subprotocol
        )
    }

    /// Returns a copy with updated terminal dimensions and `lastActivityAt`.
    public func withSize(rows: Int, cols: Int, lastActivityAt: String) -> Self {
        precondition(rows >= 1, "rows must be >= 1")
        precondition(cols >= 1, "cols must be >= 1")
        return Self(
            id: id,
            kind: kind,
            kubernetesContextId: kubernetesContextId,
            targetRef: targetRef,
            command: command,
            tty: tty,
            stdin: stdin,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            status: status,
            exitCode: exitCode,
            sizeRows: rows,
            sizeCols: cols,
            subprotocol: subprotocol
        )
    }

    /// Returns a copy with the negotiated subprotocol recorded.
    public func withSubprotocol(_ proto: ExecSubprotocol) -> Self {
        Self(
            id: id,
            kind: kind,
            kubernetesContextId: kubernetesContextId,
            targetRef: targetRef,
            command: command,
            tty: tty,
            stdin: stdin,
            createdAt: createdAt,
            lastActivityAt: lastActivityAt,
            status: status,
            exitCode: exitCode,
            sizeRows: sizeRows,
            sizeCols: sizeCols,
            subprotocol: proto
        )
    }
}
