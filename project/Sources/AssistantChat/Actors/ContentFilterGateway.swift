// Actors/ContentFilterGateway.swift — assistant_chat bounded context
// DDD role: DomainService (Layer 3 of ADR-0048 prompt injection defence)
// ADR ref: ADR-0048 (LLM prompt injection defence — Layer 3: content-filter gateway)

import Dependencies
import Foundation
import Logging
import SharedKernel

// MARK: - InjectionPattern

/// A single named denial pattern used by `ContentFilterGateway`.
///
/// Patterns map directly to the `PI-NNN` identifiers defined in ADR-0048 §Layer 3.
private struct InjectionPattern: Sendable {
    let id: String
    let regex: NSRegularExpression

    init(id: String, pattern: String) throws {
        self.id = id
        self.regex = try NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }
}

// MARK: - CircuitBreakerState

/// Per-session circuit-breaker state tracking violation timestamps.
private struct CircuitBreakerState: Sendable {
    /// Timestamps of recent violations inside the observation window.
    var violationTimestamps: [Date] = []
    /// When non-nil, the session is blocked until this date.
    var blockedUntil: Date?
}

// MARK: - ContentFilterGateway

/// Layer 3 of the ADR-0048 defence-in-depth model.
///
/// Evaluates cluster-origin strings against a set of denial regex patterns
/// (PI-001 through PI-007) and applies a score-based blocking decision.
/// Suspected injections trigger a `PromptInjectionSuspected` cross-context
/// domain event on the `DomainEventBusPort` and update the per-session
/// circuit breaker.
///
/// Circuit breaker: 3 violations within 60 seconds blocks the session for
/// 5 minutes. Each session's counter is independent.
///
/// The gateway implements `PromptInjectionFilterPort`, replacing the
/// `UnimplementedPromptInjectionFilterPort` placeholder as the `liveValue`.
public actor ContentFilterGateway: PromptInjectionFilterPort {
    // MARK: Constants

    private static let violationWindowSeconds: TimeInterval = 60
    private static let violationThreshold: Int = 3
    private static let blockDurationSeconds: TimeInterval = 300

    // MARK: State

    private var circuitBreakers: [UUID: CircuitBreakerState] = [:]

    // MARK: Dependencies

    @Dependency(\.domainEventBus) private var eventBus
    private let logger: Logger

    // MARK: Patterns

    private let patterns: [InjectionPattern]

    // MARK: - Init

    /// Initialises the gateway with the ADR-0048 denial pattern set.
    ///
    /// Regex compilation uses only static, validated patterns from ADR-0048;
    /// the init is effectively infallible but logs an error and produces an
    /// empty pattern set if construction fails at runtime.
    public init() {
        self.logger = Logger(label: "assistant_chat.ContentFilterGateway")
        if let built = try? Self.buildPatterns() {
            self.patterns = built
        } else {
            Logger(label: "assistant_chat.ContentFilterGateway.init")
                .error("Failed to compile injection patterns; Layer 3 disabled.")
            self.patterns = []
        }
    }

    // MARK: - PromptInjectionFilterPort

    /// Evaluates `input.payload` against all denial patterns and updates the
    /// circuit breaker for `input.sessionId`.
    ///
    /// Scoring: each matched pattern contributes `1.0 / patternCount`. Score
    /// >= 0.7 triggers denial; an empty match set is always allowed.
    ///
    /// - Parameter input: Sanitized payload plus telemetry metadata.
    /// - Returns: A `FilterResult` with `allow` and `matchedPatterns`.
    public func evaluate(input: FilterInput) async throws -> FilterResult {
        guard !isBlocked(sessionId: input.sessionId) else {
            logger.warning(
                "Session blocked by circuit breaker",
                metadata: ["sessionId": "\(input.sessionId)"]
            )
            return FilterResult(allow: false, matchedPatterns: ["CIRCUIT_BREAKER"])
        }

        let matched = matchedPatternIds(in: input.payload)
        let suspicionScore = score(for: matched)
        let allow = suspicionScore < 0.7 && matched.isEmpty

        if !allow {
            recordViolation(sessionId: input.sessionId)
            await emitEvent(input: input, matched: matched)
        }

        return FilterResult(allow: allow, matchedPatterns: matched)
    }

    // MARK: - Private evaluation

    private func matchedPatternIds(in payload: String) -> [String] {
        let range = NSRange(payload.startIndex..., in: payload)
        return patterns.compactMap { pattern in
            pattern.regex.firstMatch(in: payload, range: range) != nil ? pattern.id : nil
        }
    }

    private func score(for matchedIds: [String]) -> Double {
        guard !patterns.isEmpty else { return 0.0 }
        return Double(matchedIds.count) / Double(patterns.count)
    }

    // MARK: - Circuit breaker

    private func isBlocked(sessionId: UUID) -> Bool {
        guard let state = circuitBreakers[sessionId],
              let blockedUntil = state.blockedUntil else {
            return false
        }
        return Date() < blockedUntil
    }

    private func recordViolation(sessionId: UUID) {
        let now = Date()
        let cutoff = now.addingTimeInterval(-Self.violationWindowSeconds)
        var state = circuitBreakers[sessionId] ?? CircuitBreakerState()

        state.violationTimestamps = state.violationTimestamps.filter { $0 > cutoff }
        state.violationTimestamps.append(now)

        if state.violationTimestamps.count >= Self.violationThreshold {
            state.blockedUntil = now.addingTimeInterval(Self.blockDurationSeconds)
            logger.warning(
                "Circuit breaker tripped",
                metadata: [
                    "sessionId": "\(sessionId)",
                    "violations": "\(state.violationTimestamps.count)",
                ]
            )
        }

        circuitBreakers[sessionId] = state
    }

    // MARK: - Event emission

    private func emitEvent(input: FilterInput, matched: [String]) async {
        let occurredAt = ISO8601DateFormatter().string(from: Date())
        let excerpt = String(input.payload.prefix(64))
        let patternId = matched.first ?? "SCORE_THRESHOLD"

        let event = makeInjectionDomainEvent(
            sessionId: input.sessionId,
            patternId: patternId,
            source: input.source,
            excerpt: excerpt,
            matchedPatterns: matched,
            occurredAt: occurredAt
        )

        do {
            try await eventBus.publish(event, sourceContext: "assistant_chat")
        } catch {
            logger.error(
                "Failed to publish PromptInjectionSuspected event",
                metadata: ["error": "\(error)"]
            )
        }
    }

    // MARK: - Pattern factory

    private static func buildPatterns() throws -> [InjectionPattern] {
        let definitions: [(String, String)] = [
            ("PI-001", #"ignore.{0,20}previous"#),
            ("PI-002", #"you are now"#),
            ("PI-003", #"(?m)^system:"#),
            ("PI-004", #"<\|im_start\|>"#),
            ("PI-005", #"disregard.{0,20}(instructions|above|prompt)"#),
            ("PI-006", #"new persona"#),
            ("PI-007", #"act as (if you were|an?\s)"#),
        ]
        return try definitions.map { id, pattern in
            try InjectionPattern(id: id, pattern: pattern)
        }
    }
}

// MARK: - ContentFilterGatewayError

/// Errors raised by `ContentFilterGateway` initialization.
public enum ContentFilterGatewayError: Error, Sendable {
    /// One or more denial pattern regexes failed to compile.
    case patternCompilationFailed(detail: String)
}

// MARK: - InjectionSuspectedDomainEvent

/// Local alias for the cross-context `PromptInjectionSuspected` domain event.
///
/// Named distinctly to avoid shadowing `AssistantChat.PromptInjectionSuspected`,
/// which is a plain value object without `DomainEvent` conformance.
/// The wire format and CUE schema are identical to the SharedKernel version
/// (ADR-0048 §Telemetry).
private struct InjectionSuspectedDomainEvent: DomainEvent {
    struct Payload: Sendable, Codable, Hashable {
        let sessionId: String
        let patternId: String
        let source: String
        let sanitizedExcerpt: String
        let matchedPatterns: [String]
    }

    let envelope: EventEnvelope
    let payload: Payload
}

/// Constructs an `InjectionSuspectedDomainEvent` from primitives.
private func makeInjectionDomainEvent(
    sessionId: UUID,
    patternId: String,
    source: String,
    excerpt: String,
    matchedPatterns: [String],
    occurredAt: String
) -> InjectionSuspectedDomainEvent {
    let payload = InjectionSuspectedDomainEvent.Payload(
        sessionId: sessionId.uuidString,
        patternId: patternId,
        source: source,
        sanitizedExcerpt: excerpt,
        matchedPatterns: matchedPatterns
    )
    let envelope = EventEnvelope(
        eventId: UUIDv7.generate().uuidString,
        eventType: "assistant_chat.PromptInjectionSuspected",
        sourceContext: "assistant_chat",
        occurredAt: occurredAt
    )
    return InjectionSuspectedDomainEvent(envelope: envelope, payload: payload)
}
