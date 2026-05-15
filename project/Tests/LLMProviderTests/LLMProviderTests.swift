import XCTest
@testable import LLMProvider

final class LLMProviderSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(LLMProvider.moduleVersion.isEmpty)
    }
}
