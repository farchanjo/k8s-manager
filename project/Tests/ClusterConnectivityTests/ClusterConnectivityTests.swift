import XCTest
@testable import ClusterConnectivity

final class ClusterConnectivitySmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(ClusterConnectivity.moduleVersion.isEmpty)
    }
}
