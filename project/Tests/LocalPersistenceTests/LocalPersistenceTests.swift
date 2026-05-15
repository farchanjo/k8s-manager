import XCTest
@testable import LocalPersistence

final class LocalPersistenceSmokeTests: XCTestCase {
    func test_moduleVersionIsNonEmpty() {
        XCTAssertFalse(LocalPersistence.moduleVersion.isEmpty)
    }
}
