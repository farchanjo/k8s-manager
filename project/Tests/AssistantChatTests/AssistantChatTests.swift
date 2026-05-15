import XCTest
@testable import AssistantChat

final class AssistantChatSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(AssistantChat.moduleVersion.isEmpty)
    }
}
