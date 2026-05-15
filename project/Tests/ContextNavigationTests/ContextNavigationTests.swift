import XCTest
@testable import ContextNavigation

final class ContextNavigationSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(ContextNavigation.moduleVersion.isEmpty)
    }
}
