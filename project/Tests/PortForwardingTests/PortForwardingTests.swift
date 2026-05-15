import XCTest
@testable import PortForwarding

final class PortForwardingSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(PortForwarding.moduleVersion.isEmpty)
    }
}
