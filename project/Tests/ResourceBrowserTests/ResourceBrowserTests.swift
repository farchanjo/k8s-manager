import XCTest
@testable import ResourceBrowser

final class ResourceBrowserSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(ResourceBrowser.moduleVersion.isEmpty)
    }
}
