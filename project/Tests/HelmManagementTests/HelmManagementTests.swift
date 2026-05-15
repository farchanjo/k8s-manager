import XCTest
@testable import HelmManagement

final class HelmManagementSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(HelmManagement.moduleVersion.isEmpty)
    }
}
