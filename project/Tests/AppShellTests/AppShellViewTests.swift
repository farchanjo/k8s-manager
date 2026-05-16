// AppShellViewTests.swift — smoke tests for Feature enum
// Target: AppShellTests
import XCTest
@testable import AppShell

final class FeatureTests: XCTestCase {
    /// Every `Feature` case must expose a unique `rawValue`-derived `id`.
    func test_allFeaturesHaveDistinctIds() {
        let ids = Feature.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Duplicate Feature.id detected")
    }

    /// Every `Feature` case must provide a non-empty sidebar label.
    func test_allFeaturesHaveNonEmptyTitle() {
        XCTAssertTrue(
            Feature.allCases.allSatisfy { !$0.title.isEmpty },
            "One or more Feature cases have an empty title"
        )
    }

    /// Every `Feature` case must name a valid SF Symbol (non-empty string).
    func test_allFeaturesHaveSystemImage() {
        XCTAssertTrue(
            Feature.allCases.allSatisfy { !$0.systemImage.isEmpty },
            "One or more Feature cases have an empty systemImage"
        )
    }
}
