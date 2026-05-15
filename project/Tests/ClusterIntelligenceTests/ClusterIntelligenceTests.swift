import XCTest
@testable import ClusterIntelligence

final class ClusterIntelligenceSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(ClusterIntelligence.moduleVersion.isEmpty)
    }
}
