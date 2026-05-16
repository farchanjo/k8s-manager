// Domain/MCPInvocation.swift — cluster_intelligence bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/cluster_intelligence/schemas/mcp_invocation.cue
// Narrative ref: domain/narrative.md §Ubiquitous language — Invocation

import Foundation
import SharedKernel

// MARK: - InvocationId

/// Opaque UUIDv7 identity for one MCP tool execution.
public struct InvocationId: Hashable, Sendable, Codable {
    public let rawValue: UUID
    public init(_ rawValue: UUID) { self.rawValue = rawValue }

    /// Generates a new UUIDv7 using the shared-kernel generator.
    public static func generate(now: Date = Date()) -> InvocationId {
        InvocationId(UUIDv7.generate(now: now))
    }
}

// MARK: - MCPOutcome

/// The result of one tool execution.
///
/// Mirrors `#MCPOutcome` from `mcp_invocation.cue`. Exactly one case is set;
/// the discriminant maps to the CUE `kind` field.
public enum MCPOutcome: Hashable, Sendable, Codable {
    /// The tool returned a result within policy and size limits.
    case succeeded(SucceededPayload)
    /// The policy gate rejected the call before any Kubernetes API traffic.
    case deniedByPolicy(DeniedByPolicyPayload)
    /// The Kubernetes API returned an error or the tool function threw.
    case failed(FailedPayload)
    /// The caller cancelled the task within the 200 ms propagation window.
    case cancelled

    // MARK: Nested payloads

    /// Payload for the `succeeded` outcome.
    ///
    /// Mirrors `#OutcomeSucceeded` from `mcp_invocation.cue`.
    public struct SucceededPayload: Hashable, Sendable, Codable {
        /// UTF-8 JSON body returned to the MCP host.
        public let resultJSON: String
        /// Byte count of `resultJSON` before truncation (if any).
        public let resultBytes: Int
        /// `true` when `resultJSON` ends with the truncation marker
        /// `{"_truncated":true,"_omittedBytes":<n>}`.
        public let truncated: Bool
        /// HTTP status code reported by the Kubernetes API server.
        public let kubernetesStatusCode: Int

        public init(
            resultJSON: String,
            resultBytes: Int,
            truncated: Bool,
            kubernetesStatusCode: Int
        ) {
            self.resultJSON = resultJSON
            self.resultBytes = resultBytes
            self.truncated = truncated
            self.kubernetesStatusCode = kubernetesStatusCode
        }
    }

    /// Payload for the `deniedByPolicy` outcome.
    ///
    /// Mirrors `#OutcomeDeniedByPolicy` from `mcp_invocation.cue`.
    public struct DeniedByPolicyPayload: Hashable, Sendable, Codable {
        /// Deny-rule identifier from the Rego policy, e.g.
        /// `"mutating_verb_forbidden"`, `"tool_not_registered"`.
        public let rule: String
        /// Human-readable detail surfaced to the operator; never includes
        /// credential material.
        public let detail: String

        public init(rule: String, detail: String) {
            self.rule = rule
            self.detail = detail
        }
    }

    /// Payload for the `failed` outcome.
    ///
    /// Mirrors `#OutcomeFailed` from `mcp_invocation.cue`.
    public struct FailedPayload: Hashable, Sendable, Codable {
        /// HTTP status code from the Kubernetes API server, when present.
        public let kubernetesStatusCode: Int?
        /// Operator-facing reason. MUST NOT contain credential material.
        public let reason: String

        public init(kubernetesStatusCode: Int? = nil, reason: String) {
            self.kubernetesStatusCode = kubernetesStatusCode
            self.reason = reason
        }
    }
}

// MARK: - MCPInvocation

/// Immutable record of one MCP tool execution.
///
/// Mirrors `#MCPInvocation` from `mcp_invocation.cue`. Acts as the wire-log
/// entry persisted by `local_persistence` and surfaced in the diagnostics
/// panel. No bearer tokens, client certificates, or label values containing
/// the substring `secret` may appear in any field.
public struct MCPInvocation: Hashable, Sendable, Codable {
    /// Unique identifier for this invocation (UUIDv7).
    public let id: InvocationId
    /// Snake-case tool name matching the registry entry.
    public let toolName: String
    /// RFC 3339 timestamp at which the MCP host dispatched the call.
    public let requestedAtRFC3339: String
    /// RFC 3339 timestamp at which the outcome was recorded; `nil` until
    /// the call completes.
    public let completedAtRFC3339: String?
    /// The kubeconfig context this call ran against.
    public let kubernetesContextId: ContextId
    /// Validated JSON arguments supplied by the model (post-schema check).
    public let argumentsJSON: String
    /// Result of the tool execution.
    public let outcome: MCPOutcome

    public init(
        id: InvocationId,
        toolName: String,
        requestedAtRFC3339: String,
        completedAtRFC3339: String? = nil,
        kubernetesContextId: ContextId,
        argumentsJSON: String,
        outcome: MCPOutcome
    ) {
        self.id = id
        self.toolName = toolName
        self.requestedAtRFC3339 = requestedAtRFC3339
        self.completedAtRFC3339 = completedAtRFC3339
        self.kubernetesContextId = kubernetesContextId
        self.argumentsJSON = argumentsJSON
        self.outcome = outcome
    }
}
