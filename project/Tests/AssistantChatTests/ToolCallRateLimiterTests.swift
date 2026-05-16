// ToolCallRateLimiterTests.swift — assistant_chat bounded context
// XCTest coverage: ToolCallRateLimiter rolling-window semantics (ADR-0043).

import Foundation
import XCTest
@testable import AssistantChat

// MARK: - ToolCallRateLimiterTests

final class ToolCallRateLimiterTests: XCTestCase {
    // MARK: - Helpers

    private func makeDate(secondsFromNow delta: TimeInterval = 0) -> Date {
        Date(timeIntervalSinceReferenceDate: 1_000_000 + delta)
    }

    // MARK: - Test 1: Construction smoke

    func test_init_createsLimiter() async {
        let limiter = ToolCallRateLimiter()
        // Smoke: actor is reachable and first attempt is allowed.
        let sessionId = UUID()
        let result = await limiter.attempt(sessionId: sessionId, now: makeDate())
        XCTAssertEqual(result, .allowed)
    }

    // MARK: - Test 2: First call is always allowed

    func test_attempt_firstCall_isAllowed() async {
        let limiter = ToolCallRateLimiter()
        let sessionId = UUID()
        let now = makeDate()

        let decision = await limiter.attempt(sessionId: sessionId, now: now)

        XCTAssertEqual(decision, .allowed)
    }

    // MARK: - Test 3: 20 calls allowed; 21st denied with retryAfter

    func test_attempt_21stCall_isDeniedWithRetryAfter() async {
        let limiter = ToolCallRateLimiter()
        let sessionId = UUID()
        let base = makeDate()

        // Issue 20 calls at the same instant (all within the window).
        for i in 0..<20 {
            let decision = await limiter.attempt(
                sessionId: sessionId,
                now: base.addingTimeInterval(Double(i) * 0.01)
            )
            XCTAssertEqual(decision, .allowed, "Call \(i + 1) should be allowed")
        }

        // 21st call at 1 second after base — still within 60-second window.
        let decision = await limiter.attempt(
            sessionId: sessionId,
            now: base.addingTimeInterval(1)
        )

        guard case .denied(let retryAfter) = decision else {
            XCTFail("Expected .denied but got .allowed")
            return
        }
        XCTAssertGreaterThan(retryAfter, 0, "retryAfterSeconds must be positive")
        XCTAssertLessThanOrEqual(retryAfter, 60, "retryAfterSeconds must not exceed window size")
    }

    // MARK: - Test 4: Window slides — counter resets after 60 s

    func test_attempt_afterWindowExpiry_allowsNewCalls() async {
        let limiter = ToolCallRateLimiter()
        let sessionId = UUID()
        let base = makeDate()

        // Fill the quota at t=0.
        for _ in 0..<20 {
            _ = await limiter.attempt(sessionId: sessionId, now: base)
        }

        // At t=61 all prior timestamps are outside the 60-second window.
        let future = base.addingTimeInterval(61)
        let decision = await limiter.attempt(sessionId: sessionId, now: future)

        XCTAssertEqual(decision, .allowed, "Should be allowed after window slides past all old timestamps")
    }

    // MARK: - Test 5: Multiple sessions tracked independently

    func test_attempt_multipleSessionsAreIndependent() async {
        let limiter = ToolCallRateLimiter()
        let sessionA = UUID()
        let sessionB = UUID()
        let now = makeDate()

        // Exhaust quota for sessionA.
        for _ in 0..<20 {
            _ = await limiter.attempt(sessionId: sessionA, now: now)
        }
        let deniedForA = await limiter.attempt(sessionId: sessionA, now: now.addingTimeInterval(1))
        XCTAssertEqual(deniedForA, .denied(retryAfterSeconds: 59))

        // sessionB should still have a full budget.
        let allowedForB = await limiter.attempt(sessionId: sessionB, now: now)
        XCTAssertEqual(allowedForB, .allowed, "SessionB must not be affected by sessionA's quota")
    }

    // MARK: - Test 6: retryAfterSeconds computation accuracy

    func test_attempt_retryAfterSeconds_pointsToOldestSlot() async {
        let limiter = ToolCallRateLimiter()
        let sessionId = UUID()
        let base = makeDate()

        // First call at t=0 (oldest), rest at t=1.
        _ = await limiter.attempt(sessionId: sessionId, now: base)
        for _ in 1..<20 {
            _ = await limiter.attempt(sessionId: sessionId, now: base.addingTimeInterval(1))
        }

        // 21st call at t=30 — oldest is at t=0, which expires at t=60.
        let callAt30 = base.addingTimeInterval(30)
        let decision = await limiter.attempt(sessionId: sessionId, now: callAt30)

        guard case .denied(let retryAfter) = decision else {
            XCTFail("Expected .denied")
            return
        }
        // Oldest timestamp is base (t=0); window expires at t=60; call is at t=30.
        // retryAfter = ceil(60 - 30) = 30.
        XCTAssertEqual(retryAfter, 30, "retryAfterSeconds should point to the oldest window slot expiry")
    }

    // MARK: - Test 7: clearSession resets budget

    func test_clearSession_resetsQuotaForSession() async {
        let limiter = ToolCallRateLimiter()
        let sessionId = UUID()
        let now = makeDate()

        // Exhaust quota.
        for _ in 0..<20 {
            _ = await limiter.attempt(sessionId: sessionId, now: now)
        }
        let beforeClear = await limiter.attempt(sessionId: sessionId, now: now.addingTimeInterval(1))
        XCTAssertEqual(beforeClear, .denied(retryAfterSeconds: 59))

        // Clear and retry immediately.
        await limiter.clearSession(sessionId: sessionId)
        let afterClear = await limiter.attempt(sessionId: sessionId, now: now.addingTimeInterval(1))
        XCTAssertEqual(afterClear, .allowed, "Cleared session should start with fresh budget")
    }
}
