// Ports/ToolPolicyPort.swift — cluster_intelligence bounded context
// DDD role: Port (outbound — Rego policy evaluation for tool allow-listing)
// ADR ref: ADR-0009 §Decision outcome — policy gate
// Narrative ref: domain/narrative.md §Ubiquitous language — Policy gate, §Invariants

import Foundation
import SharedKernel

// MARK: - PolicyEvaluationRequest

/// The input to a policy evaluation for one tool invocation.
///
/// Consumed by `ToolPolicyPort` implementations. Contains everything the Rego
/// policy needs to decide allow or deny without accessing any external state.
public struct PolicyEvaluationRequest: Sendable {
    /// The tool being invoked.
    public let tool: MCPTool
    /// The validated JSON arguments (post-schema check).
    public let argumentsJSON: String
    /// The Kubernetes context the call targets.
    public let kubernetesContextId: ContextId

    public init(
        tool: MCPTool,
        argumentsJSON: String,
        kubernetesContextId: ContextId
    ) {
        self.tool = tool
        self.argumentsJSON = argumentsJSON
        self.kubernetesContextId = kubernetesContextId
    }
}

// MARK: - PolicyDecision

/// The output of a policy evaluation.
///
/// Invariant: a `denied` decision MUST be returned before any Kubernetes
/// HTTP request is made; a denied invocation MUST NOT produce API traffic.
public enum PolicyDecision: Sendable {
    /// The invocation is allowed to proceed to the Kubernetes API.
    case allowed
    /// The invocation is denied; `rule` names the Rego deny-rule that fired.
    case denied(rule: String, detail: String)
}

// MARK: - ToolPolicyPort

/// Evaluates Rego-based allow/deny decisions for inbound tool calls.
///
/// Declared in the domain core; implemented by a Rego adapter
/// (not in the domain core). The domain core never imports the Rego runtime
/// or any OPA Swift bindings.
///
/// The port is invoked synchronously inside the dispatch loop, *after* input
/// validation and *before* any `KubernetesApiPort` call. A `denied` decision
/// short-circuits the dispatch and records a `deniedByPolicy` `MCPOutcome`.
public protocol ToolPolicyPort: Sendable {
    /// Evaluates whether the given tool invocation is allowed.
    ///
    /// - Parameter request: The invocation details to evaluate.
    /// - Returns: A `PolicyDecision` indicating allow or deny.
    /// - Throws: `ToolPolicyError` for failures in the policy engine itself
    ///   (not for deny decisions — those are expressed as
    ///   `PolicyDecision.denied`).
    func evaluate(_ request: PolicyEvaluationRequest) async throws -> PolicyDecision
}

// MARK: - ToolPolicyError

/// Errors raised by `ToolPolicyPort` implementations.
public enum ToolPolicyError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
    /// The Rego policy file could not be loaded or compiled.
    case policyLoadFailed(detail: String)
    /// The evaluation engine returned an unexpected runtime error.
    case evaluationFailed(detail: String)
}

// MARK: - UnimplementedToolPolicyPort

/// Crash-fast sentinel that denies every call until an adapter is registered.
///
/// Returning `denied` (rather than throwing) keeps the invariant that no
/// Kubernetes API traffic flows before a real policy is in place.
public struct UnimplementedToolPolicyPort: ToolPolicyPort {
    public init() {}

    public func evaluate(_ request: PolicyEvaluationRequest) async throws -> PolicyDecision {
        throw ToolPolicyError.unimplemented
    }
}
