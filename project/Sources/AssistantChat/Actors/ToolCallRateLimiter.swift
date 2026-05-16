// Actors/ToolCallRateLimiter.swift — assistant_chat bounded context
// DDD role: DomainService (Swift actor — ADR-0043)
// ADR ref: ADR-0043 — Per-session assistant tool-call rate limiting

import Foundation
import SharedKernel

// MARK: - RateLimitDecision

/// Result of a rate-limit admission check for one tool invocation.
///
/// Returned by ``ToolCallRateLimiter/attempt(sessionId:now:)``. A `.denied`
/// result MUST be surfaced to the model as an `mcp.tool_rate_limited` envelope;
/// the call MUST NOT reach `ToolDispatcherPort`.
public enum RateLimitDecision: Sendable, Equatable {
    /// The invocation is within the per-session quota; proceed to dispatch.
    case allowed

    /// The per-session quota is exhausted.
    ///
    /// - Parameter retryAfterSeconds: Seconds until the oldest recorded
    ///   timestamp ages out of the 60-second window, freeing one slot.
    case denied(retryAfterSeconds: Int)
}

// MARK: - ToolCallRateLimiter

/// Per-session sliding-window rate limiter for assistant tool calls.
///
/// Enforces the 20-calls-per-60-second quota mandated by ADR-0043.
/// Each `ChatSession` (identified by `UUID`) maintains an independent
/// timestamp log; sessions never share budget.
///
/// Thread safety: this is a Swift `actor`; all state mutations are
/// serialised by the actor's executor.
public actor ToolCallRateLimiter {
    // MARK: Constants

    private let windowSeconds: TimeInterval = 60
    private let cap: Int = 20

    // MARK: State

    /// Maps each session UUID to the timestamps of tool calls still inside
    /// the rolling window. Entries are lazily evicted on each `attempt` call.
    private var timestamps: [UUID: [Date]] = [:]

    // MARK: - Init

    /// Creates a rate limiter with default ADR-0043 parameters (20/60 s).
    public init() {}

    // MARK: - Attempt

    /// Performs an admission check for one tool-call attempt.
    ///
    /// Records the call if admitted. Evicts stale entries on every call to
    /// prevent unbounded memory growth.
    ///
    /// - Parameters:
    ///   - sessionId: The `ChatSession.id` issuing the tool call.
    ///   - now: Wall-clock reference; defaults to `Date()`. Injected in tests.
    /// - Returns: `.allowed` when under quota; `.denied(retryAfterSeconds:)`
    ///   otherwise.
    public func attempt(sessionId: UUID, now: Date = Date()) async -> RateLimitDecision {
        let cutoff = now.addingTimeInterval(-windowSeconds)

        var window = timestamps[sessionId, default: []]
        window = window.filter { $0 > cutoff }

        guard window.count < cap else {
            let oldest = window.min() ?? now
            let retryAfter = max(1, Int(ceil(windowSeconds - now.timeIntervalSince(oldest))))
            timestamps[sessionId] = window
            return .denied(retryAfterSeconds: retryAfter)
        }

        window.append(now)
        timestamps[sessionId] = window
        return .allowed
    }

    // MARK: - Session cleanup

    /// Discards all recorded timestamps for `sessionId`.
    ///
    /// Call when a `ChatSession` closes to release memory. The next session
    /// for the same `id` begins with a fresh budget (ADR-0043 §Consequences).
    public func clearSession(sessionId: UUID) {
        timestamps.removeValue(forKey: sessionId)
    }
}
