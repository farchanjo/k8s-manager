// Domain/PromptInjectionEvent.swift — assistant_chat bounded context
// DDD role: ValueObject / DomainEvent
// CUE source: docs/arch/contexts/assistant_chat/schemas/prompt_injection_event.cue

import Foundation

// MARK: - PromptInjectionSuspected

/// Domain event emitted by `ContentFilterGateway` when Layer 3 of the
/// ADR-0048 defence-in-depth model matches a denial pattern in a
/// cluster-origin string before it is injected into the LLM context.
///
/// Published on `DomainEventBusActor` and written to the diagnostics ring
/// buffer (ADR-0027). Only the pattern ID and a short sanitized excerpt are
/// captured; the full adversarial payload is never stored.
///
/// Consumed by `analytics_dashboard` (security-event telemetry widget) and
/// `app_shell` (optional operator notification toast).
///
/// Reference: ADR-0048 (LLM prompt injection defence).
public struct PromptInjectionSuspected: Hashable, Sendable, Codable {
    /// UUIDv7 of the active chat session in which the suspected injection
    /// was detected.
    public let sessionId: UUID

    /// Identifier of the first matched denial rule (e.g. `"PI-001"`).
    /// Allows operators to distinguish which attack technique was attempted.
    public let patternId: String

    /// Kubernetes resource identity from which the cluster-origin payload was
    /// derived, in `"<Kind>/<name>"` form (e.g. `"ConfigMap/my-config"`).
    /// Empty string when the source cannot be determined.
    public let source: String

    /// First 64 characters of the sanitized (post-Layer-1) payload that
    /// triggered the denial, providing triage context without storing the full
    /// adversarial content.
    public let sanitizedExcerpt: String

    /// RFC 3339 UTC timestamp at which `ContentFilterGateway` detected the
    /// pattern match.
    public let occurredAt: String

    /// Complete set of pattern IDs that fired for this payload. At least one
    /// entry is always present.
    public let matchedPatterns: [String]

    public init(
        sessionId: UUID,
        patternId: String,
        source: String,
        sanitizedExcerpt: String,
        occurredAt: String,
        matchedPatterns: [String]
    ) {
        self.sessionId = sessionId
        self.patternId = patternId
        self.source = source
        self.sanitizedExcerpt = sanitizedExcerpt
        self.occurredAt = occurredAt
        self.matchedPatterns = matchedPatterns
    }
}
