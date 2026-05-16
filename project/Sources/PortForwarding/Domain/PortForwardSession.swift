// Domain/PortForwardSession.swift — port_forwarding bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/port_forwarding/schemas/port_forward_session.cue
// ADR ref: ADR-0014 (lifecycle state machine and wire protocol)

import Foundation
import SharedKernel

// MARK: - SessionStatus

/// Lifecycle state of a ``PortForwardSession`` aggregate.
///
/// Legal transitions (ADR-0014):
/// - `opening` → `running` — WebSocket upgrade succeeded, listener(s) bound.
/// - `opening` → `error` — WebSocket upgrade or bind failed.
/// - `running` → `closing` — operator called `stop()` or app is quitting.
/// - `running` → `error` — WebSocket closed unexpectedly.
/// - `closing` → `closed` — listener closed, WebSocket close handshake complete.
///
/// There is no transition from `error` or `closed` back to `opening`.
public enum SessionStatus: String, Hashable, Sendable, Codable {
    /// WebSocket upgrade in progress; no listener is bound yet.
    case opening
    /// Upgrade succeeded; at least one listener is accepting TCP connections.
    case running
    /// `stop()` called; cooperative shutdown in progress.
    case closing
    /// Listener closed and WebSocket close handshake complete.
    case closed
    /// Non-recoverable failure; session must not be reactivated.
    case error
}

// MARK: - ForwardTarget

/// Kubernetes resource that is the tunnel endpoint for a port-forward session.
///
/// Mirrors the `#PodTarget | #ServiceTarget` disjunction in `port_forward_session.cue`.
public enum ForwardTarget: Hashable, Sendable, Codable {
    /// Direct reference to a Kubernetes Pod.
    case pod(PodTarget)
    /// Kubernetes Service resolved to a backing Pod at session-open time.
    case service(ServiceTarget)

    /// Returns the namespace common to both target variants.
    public var namespace: String {
        switch self {
        case .pod(let t): t.namespace
        case .service(let t): t.namespace
        }
    }
}

// MARK: - PodTarget

/// Direct reference to a Kubernetes Pod as the tunnel endpoint.
///
/// Mirrors `#PodTarget` from `port_forward_session.cue`.
public struct PodTarget: Hashable, Sendable, Codable {
    /// Kubernetes namespace of the target Pod.
    public let namespace: String
    /// Name of the target Pod (valid Kubernetes DNS label).
    public let podName: String

    public init(namespace: String, podName: String) {
        self.namespace = namespace
        self.podName = podName
    }
}

// MARK: - ServiceTarget

/// Kubernetes Service as the logical tunnel endpoint, resolved to a backing Pod
/// at session-open time via `ServiceEndpointReaderPort`.
///
/// Mirrors `#ServiceTarget` from `port_forward_session.cue`.
public struct ServiceTarget: Hashable, Sendable, Codable {
    /// Kubernetes namespace of the Service.
    public let namespace: String
    /// Name of the Kubernetes Service.
    public let serviceName: String
    /// Pod name selected by the Service endpoint selector at session-open time.
    /// `nil` until `ServiceEndpointReaderPort` resolution completes.
    public let resolvedPodName: String?

    public init(
        namespace: String,
        serviceName: String,
        resolvedPodName: String? = nil
    ) {
        self.namespace = namespace
        self.serviceName = serviceName
        self.resolvedPodName = resolvedPodName
    }
}

// MARK: - PortMapping

/// A single `localPort:remotePort` pair within a session.
///
/// The position of a `PortMapping` in `portMappings` determines its
/// `portIndex` (0-based) used in the binary frame header of the
/// `portforward.k8s.io` WebSocket subprotocol (ADR-0014 §Wire protocol).
///
/// Mirrors `#PortMapping` from `port_forward_session.cue`.
public struct PortMapping: Hashable, Sendable, Codable {
    /// TCP port bound on the local machine. Range 1–65535. When the operator
    /// specifies 0, the kernel assigns a dynamic port; the actor replaces the 0
    /// with the assigned port after `bind(2)` completes.
    public let localPort: Int
    /// TCP port inside the Pod to forward traffic to. Range 1–65535.
    public let remotePort: Int
    /// Transport-layer protocol. Only `"tcp"` is supported (ADR-0014 §Out of scope).
    public let `protocol`: String
    /// Local IP address the TCP listener is bound to. Defaults to `"127.0.0.1"`.
    /// Setting this to `"0.0.0.0"` exposes the tunnel on all interfaces; the UI
    /// must surface a network-exposure warning in that case.
    public let bindAddress: String

    public init(
        localPort: Int,
        remotePort: Int,
        protocol: String = "tcp",
        bindAddress: String = "127.0.0.1"
    ) {
        self.localPort = localPort
        self.remotePort = remotePort
        self.protocol = `protocol`
        self.bindAddress = bindAddress
    }

    /// Returns `true` when `bindAddress` is not the loopback address, indicating
    /// the listener is accessible beyond the local machine.
    public var isNetworkExposed: Bool {
        bindAddress != "127.0.0.1"
    }
}

// MARK: - PortForwardSession

/// Aggregate root for a single port-forward tunnel session.
///
/// Owned by exactly one `PortForwardManagerActor`. All mutations flow through
/// that actor; this value is immutable to all other components.
///
/// Invariants enforced at construction:
/// - `portMappings` is non-empty (at least one port must be forwarded).
/// - `openedAtRFC3339` is non-`nil` only when `status` is `running`, `closing`,
///   or `closed`.
/// - `closedAtRFC3339` is non-`nil` only when `status` is `closed` or `error`.
/// - Sessions reaching `closed` or `error` cannot be reactivated. A new aggregate
///   with a fresh UUIDv7 must be created.
///
/// Mirrors `#PortForwardSession` from `port_forward_session.cue`.
public struct PortForwardSession: Hashable, Sendable, Codable {
    /// UUIDv7 uniquely identifying this session. Time-ordered via `UUIDv7.generate()`.
    public let id: UUID
    /// UUIDv7 of the active kubeconfig context under which the session was opened.
    public let kubernetesContextId: UUID
    /// Kubernetes resource acting as the tunnel endpoint.
    public let target: ForwardTarget
    /// Ordered list of port mappings. Position determines `portIndex` on the wire.
    public let portMappings: [PortMapping]
    /// Current lifecycle state.
    public let status: SessionStatus
    /// RFC 3339 timestamp at which the aggregate was created (before the WebSocket
    /// handshake begins).
    public let createdAtRFC3339: String
    /// RFC 3339 timestamp at which the session transitioned to `running`.
    /// Present only when `status` is `running`, `closing`, or `closed`.
    public let openedAtRFC3339: String?
    /// RFC 3339 timestamp at which the session reached `closed` or `error`.
    /// Present only when `status` is `closed` or `error`.
    public let closedAtRFC3339: String?

    public init(
        id: UUID = UUIDv7.generate(),
        kubernetesContextId: UUID,
        target: ForwardTarget,
        portMappings: [PortMapping],
        status: SessionStatus = .opening,
        createdAtRFC3339: String,
        openedAtRFC3339: String? = nil,
        closedAtRFC3339: String? = nil
    ) {
        precondition(!portMappings.isEmpty, "PortForwardSession must have at least one port mapping")
        self.id = id
        self.kubernetesContextId = kubernetesContextId
        self.target = target
        self.portMappings = portMappings
        self.status = status
        self.createdAtRFC3339 = createdAtRFC3339
        self.openedAtRFC3339 = openedAtRFC3339
        self.closedAtRFC3339 = closedAtRFC3339
    }

    // MARK: Lifecycle transitions

    /// Returns a new session with `status` set to `running` and `openedAtRFC3339` set.
    ///
    /// - Precondition: current `status` is `opening`.
    public func opened(at timestamp: String) -> PortForwardSession {
        precondition(status == .opening, "Can only open from .opening; current: \(status)")
        return PortForwardSession(
            id: id,
            kubernetesContextId: kubernetesContextId,
            target: target,
            portMappings: portMappings,
            status: .running,
            createdAtRFC3339: createdAtRFC3339,
            openedAtRFC3339: timestamp,
            closedAtRFC3339: nil
        )
    }

    /// Returns a new session with `status` set to `closing`.
    ///
    /// - Precondition: current `status` is `running`.
    public func beginClosing() -> PortForwardSession {
        precondition(status == .running, "Can only begin closing from .running; current: \(status)")
        return PortForwardSession(
            id: id,
            kubernetesContextId: kubernetesContextId,
            target: target,
            portMappings: portMappings,
            status: .closing,
            createdAtRFC3339: createdAtRFC3339,
            openedAtRFC3339: openedAtRFC3339,
            closedAtRFC3339: nil
        )
    }

    /// Returns a new session with `status` set to `closed` and `closedAtRFC3339` set.
    ///
    /// - Precondition: current `status` is `closing`.
    public func closed(at timestamp: String) -> PortForwardSession {
        precondition(status == .closing, "Can only close from .closing; current: \(status)")
        return PortForwardSession(
            id: id,
            kubernetesContextId: kubernetesContextId,
            target: target,
            portMappings: portMappings,
            status: .closed,
            createdAtRFC3339: createdAtRFC3339,
            openedAtRFC3339: openedAtRFC3339,
            closedAtRFC3339: timestamp
        )
    }

    /// Returns a new session with `status` set to `error` and `closedAtRFC3339` set.
    ///
    /// Reachable from both `opening` and `running` (ADR-0014 §Lifecycle).
    public func failed(at timestamp: String) -> PortForwardSession {
        precondition(
            status == .opening || status == .running,
            "Can only fail from .opening or .running; current: \(status)"
        )
        return PortForwardSession(
            id: id,
            kubernetesContextId: kubernetesContextId,
            target: target,
            portMappings: portMappings,
            status: .error,
            createdAtRFC3339: createdAtRFC3339,
            openedAtRFC3339: openedAtRFC3339,
            closedAtRFC3339: timestamp
        )
    }

    /// Returns `true` when the session is in a terminal state and must not be reactivated.
    public var isTerminal: Bool {
        status == .closed || status == .error
    }
}
