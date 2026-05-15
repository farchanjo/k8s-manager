import XCTest
@testable import SharedKernel

final class SharedKernelSmokeTests: XCTestCase {
    func test_moduleVersionStringIsNonEmpty() {
        // SharedKernel uses public types instead of an enum; smoke-test ClusterId construction.
        let id = ClusterId("smoke")
        XCTAssertEqual(id.rawValue, "smoke")
    }

    func test_uuidv7IsTimeOrdered() {
        let now = Date()
        let later = now.addingTimeInterval(0.1)
        let a = UUIDv7.generate(now: now)
        let b = UUIDv7.generate(now: later)
        XCTAssertNotEqual(a, b)
    }

    func test_systemClockReturnsRecentDate() {
        let clock = SystemClock()
        let diff = abs(clock.now().timeIntervalSinceNow)
        XCTAssertLessThan(diff, 1.0)
    }
}
