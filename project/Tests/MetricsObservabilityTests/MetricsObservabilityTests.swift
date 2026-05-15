import XCTest
@testable import MetricsObservability

final class MetricsObservabilitySmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(MetricsObservability.moduleVersion.isEmpty)
    }
}
