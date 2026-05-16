// Domain/NodeDebugDescriptor.swift — terminal_session bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/terminal_session/schemas/node_debug_descriptor.cue
// ADR ref: ADR-0017 §Decision outcome, §Risks

import Foundation
import SharedKernel

// MARK: - DebugSecurityContext

/// Security context applied to the debug container's pod spec.
///
/// Mirrors `#DebugSecurityContext` from the CUE schema.
///
/// Risk note (ADR-0017): `privileged: true` grants the debug container full
/// access to the host kernel. Required for `tcpdump`, `nsenter`, `strace`, and
/// most node-level debugging workflows. A future ADR may introduce configurable
/// profiles.
public struct DebugSecurityContext: Hashable, Sendable, Codable {
    /// Whether the debug container runs in privileged mode.
    /// Always `true` in the current implementation — see ADR-0017 risk section.
    public let privileged: Bool

    public init(privileged: Bool = true) {
        self.privileged = privileged
    }
}

// MARK: - NodeDebugDescriptor

/// Immutable descriptor for the ephemeral debug Pod created during a
/// `nodeDebug` session.
///
/// Created by the domain when a node debug session is initiated. Passed to
/// `NodeDebugPort` to drive Pod creation and deletion. Immutable after
/// construction — no mutations permitted.
///
/// Invariants:
/// - `ephemeralPodName` matches `"node-debugger-<nodeName>-<8hex>"`.
/// - `hostNetwork` and `hostPID` are always `true`.
/// - `expiresAt` is always `createdAt + sessionDuration + 60 s` grace.
/// - `securityContext.privileged` is `true` in the current implementation.
public struct NodeDebugDescriptor: Hashable, Sendable, Codable {
    /// Kubernetes node this descriptor targets.
    public let nodeName: String
    /// Generated name for the debug Pod. Pattern: `node-debugger-<nodeName>-<8hex>`.
    public let ephemeralPodName: String
    /// Namespace in which the debug Pod is created. Defaults to `"default"`.
    public let namespace: String
    /// Container image used for the debug container.
    public let debugImage: String
    /// Whether the debug Pod shares the node's network namespace. Always `true`.
    public let hostNetwork: Bool
    /// Whether the debug Pod shares the node's PID namespace. Always `true`.
    public let hostPID: Bool
    /// Security context for the debug container.
    public let securityContext: DebugSecurityContext
    /// RFC 3339 timestamp after which the debug Pod should be deleted even if
    /// the parent session record is missing. Safety net against application
    /// crashes: `sessionClose + 60 s` grace.
    public let expiresAt: String

    public init(
        nodeName: String,
        ephemeralPodName: String,
        namespace: String = "default",
        debugImage: String = "nicolaka/netshoot:v0.13",
        hostNetwork: Bool = true,
        hostPID: Bool = true,
        securityContext: DebugSecurityContext = DebugSecurityContext(),
        expiresAt: String
    ) {
        self.nodeName = nodeName
        self.ephemeralPodName = ephemeralPodName
        self.namespace = namespace
        self.debugImage = debugImage
        self.hostNetwork = hostNetwork
        self.hostPID = hostPID
        self.securityContext = securityContext
        self.expiresAt = expiresAt
    }

    /// Convenience factory that generates an `ephemeralPodName` following the
    /// `"node-debugger-<nodeName>-<8hex>"` pattern.
    ///
    /// - Parameters:
    ///   - nodeName: Target node name.
    ///   - namespace: Kubernetes namespace for the debug Pod. Defaults to `"default"`.
    ///   - debugImage: Container image. Defaults to `"nicolaka/netshoot:v0.13"`.
    ///   - securityContext: Security context override. Defaults to privileged.
    ///   - expiresAt: RFC 3339 expiry timestamp.
    public static func make(
        nodeName: String,
        namespace: String = "default",
        debugImage: String = "nicolaka/netshoot:v0.13",
        securityContext: DebugSecurityContext = DebugSecurityContext(),
        expiresAt: String
    ) -> NodeDebugDescriptor {
        let shortUUID = UUIDv7.generate().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(8)
            .lowercased()
        let podName = "node-debugger-\(nodeName)-\(shortUUID)"
        return NodeDebugDescriptor(
            nodeName: nodeName,
            ephemeralPodName: podName,
            namespace: namespace,
            debugImage: debugImage,
            hostNetwork: true,
            hostPID: true,
            securityContext: securityContext,
            expiresAt: expiresAt
        )
    }
}
