import XCTest
@testable import TerminalSession

final class TerminalSessionSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(TerminalSession.moduleVersion.isEmpty)
    }
}
