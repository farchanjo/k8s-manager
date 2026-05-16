// Ports/PromptInjectionFilterPort.swift — assistant_chat bounded context
// DDD role: Port (outbound — Rego policy adapter)
// ADR ref: ADR-0048 (LLM prompt injection defence); ADR-0020 (DI strategy)

import Foundation

// MARK: - FilterInput

/// Input payload forwarded to the Rego `prompt_injection_filter` policy.
///
/// Maps to the `input` object expected by `prompt_injection_filter.rego`:
/// `input.payload`, `input.source`, `input.sessionId`.
public struct FilterInput: Sendable {
    /// Sanitized cluster-origin string to evaluate (Layer 1 output).
    public let payload: String
    /// Kubernetes resource identity (`"<Kind>/<name>"`).
    public let source: String
    /// UUIDv7 of the active chat session (for telemetry).
    public let sessionId: UUID

    public init(payload: String, source: String, sessionId: UUID) {
        self.payload = payload
        self.source = source
        self.sessionId = sessionId
    }
}

// MARK: - FilterResult

/// Decision returned by the Rego policy for one `FilterInput`.
public struct FilterResult: Sendable {
    /// `true` when no denial pattern matched; `false` blocks injection.
    public let allow: Bool
    /// Pattern IDs that fired. Empty when `allow` is `true`.
    public let matchedPatterns: [String]

    public init(allow: Bool, matchedPatterns: [String]) {
        self.allow = allow
        self.matchedPatterns = matchedPatterns
    }
}

// MARK: - PromptInjectionFilterPort

/// Evaluates a single cluster-origin string against the Layer-3 content-filter
/// policy before it is injected into the LLM context.
///
/// Declared in the domain core; implemented by an OPA adapter in infrastructure.
/// The domain core never imports the OPA runtime or any networking type.
public protocol PromptInjectionFilterPort: Sendable {
    /// Evaluates `input` against the `prompt_injection_filter` Rego bundle.
    ///
    /// - Parameter input: The sanitized payload plus telemetry metadata.
    /// - Returns: A `FilterResult` with `allow` and `matchedPatterns`.
    /// - Throws: `PromptInjectionFilterError` on evaluation failure.
    func evaluate(input: FilterInput) async throws -> FilterResult
}

// MARK: - PromptInjectionFilterError

/// Errors raised by `PromptInjectionFilterPort` implementations.
public enum PromptInjectionFilterError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
    /// The Rego bundle could not be loaded or compiled.
    case bundleError(detail: String)
    /// Policy evaluation returned an unexpected result shape.
    case evaluationError(detail: String)
}

// MARK: - UnimplementedPromptInjectionFilterPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedPromptInjectionFilterPort: PromptInjectionFilterPort {
    public init() {}

    public func evaluate(input: FilterInput) async throws -> FilterResult {
        throw PromptInjectionFilterError.unimplemented
    }
}
