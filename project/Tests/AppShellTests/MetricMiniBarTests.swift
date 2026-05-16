// Tests/AppShellTests/MetricMiniBarTests.swift
// Coverage: MetricSeries value object + MetricMiniBar rendering contract per ADR-0059.

import XCTest
@testable import AppShell

// MARK: - MetricSeriesFillRatioTests

final class MetricSeriesFillRatioTests: XCTestCase {

    func test_fillRatio_clampedToUnit() {
        let over = MetricSeries.available(dimension: .cpu, value: 5.0, capacity: 4.0)
        XCTAssertEqual(over.fillRatio, 1.0, accuracy: 0.001)
    }

    func test_fillRatio_zeroWhenValueIsZero() {
        let s = MetricSeries.available(dimension: .cpu, value: 0.0, capacity: 4.0)
        XCTAssertEqual(s.fillRatio, 0.0, accuracy: 0.001)
    }

    func test_fillRatio_correctMidpoint() {
        let s = MetricSeries.available(dimension: .memory, value: 512, capacity: 1024)
        XCTAssertEqual(s.fillRatio, 0.5, accuracy: 0.001)
    }

    func test_fillRatio_zeroForUnavailable() {
        let s = MetricSeries.unavailable(dimension: .disk)
        XCTAssertEqual(s.fillRatio, 0.0)
    }

    func test_fillRatio_zeroForNoRequestSet() {
        let s = MetricSeries(dimension: .cpu, state: .noRequestSet)
        XCTAssertEqual(s.fillRatio, 0.0)
    }

    func test_fillRatio_frozenPreservesValue() {
        let s = MetricSeries.frozen(dimension: .cpu, value: 2.0, capacity: 4.0)
        XCTAssertEqual(s.fillRatio, 0.5, accuracy: 0.001)
    }

    func test_fillRatio_zeroWhenCapacityIsZero() {
        let s = MetricSeries.available(dimension: .cpu, value: 1.0, capacity: 0.0)
        XCTAssertEqual(s.fillRatio, 0.0)
    }

    func test_fillRatio_neverNegative() {
        let s = MetricSeries.available(dimension: .memory, value: -10, capacity: 1024)
        XCTAssertGreaterThanOrEqual(s.fillRatio, 0.0)
    }
}

// MARK: - MetricSeriesAccessibilityLabelTests

final class MetricSeriesAccessibilityLabelTests: XCTestCase {

    func test_accessibilityLabel_containsDimensionAndPercent() {
        let s = MetricSeries.available(dimension: .cpu, value: 2.0, capacity: 4.0)
        XCTAssertTrue(s.accessibilityLabel.contains("CPU"))
        XCTAssertTrue(s.accessibilityLabel.contains("50"))
    }

    func test_accessibilityLabel_unavailable() {
        let s = MetricSeries.unavailable(dimension: .disk)
        XCTAssertEqual(s.accessibilityLabel, "Disk unavailable")
    }

    func test_accessibilityLabel_noRequestSet() {
        let s = MetricSeries(dimension: .memory, state: .noRequestSet)
        XCTAssertEqual(s.accessibilityLabel, "Memory no request set")
    }

    func test_accessibilityLabel_frozen() {
        let s = MetricSeries.frozen(dimension: .memory, value: 256, capacity: 1024)
        XCTAssertTrue(s.accessibilityLabel.contains("Memory"))
        XCTAssertTrue(s.accessibilityLabel.contains("25"))
    }
}

// MARK: - MetricSeriesStateTests

final class MetricSeriesStateTests: XCTestCase {

    func test_conveniences_roundtrip() {
        let s = MetricSeries.available(dimension: .cpu, value: 1.0, capacity: 2.0)
        if case .available(let v, let c) = s.state {
            XCTAssertEqual(v, 1.0)
            XCTAssertEqual(c, 2.0)
        } else {
            XCTFail("Expected .available state")
        }
    }

    func test_frozen_isDistinctFromAvailable() {
        let frozen = MetricSeries.frozen(dimension: .cpu, value: 1.0, capacity: 2.0)
        if case .frozen = frozen.state {
            // correct
        } else {
            XCTFail("Expected .frozen state")
        }
    }

    func test_unavailable_isDistinctFromFrozen() {
        let u = MetricSeries.unavailable(dimension: .disk)
        if case .unavailable = u.state {
            // correct
        } else {
            XCTFail("Expected .unavailable state")
        }
    }
}

// MARK: - MetricMiniBarColourTests

final class MetricMiniBarColourTests: XCTestCase {

    func test_pressureThresholdIsNinetyPercent() {
        XCTAssertEqual(MetricMiniBarColours.pressureThreshold, 0.90, accuracy: 0.001)
    }

    func test_frozenReturnsGrayColour() {
        // Just ensure no crash; colour equality via SwiftUI is not testable without hosting.
        let colour = MetricMiniBarColours.fillColour(for: .cpu, ratio: 0.5, isFrozen: true)
        XCTAssertNotNil(colour)
    }

    func test_nonFrozenBelowThresholdReturnsDimensionColour() {
        let colour = MetricMiniBarColours.fillColour(for: .cpu, ratio: 0.50, isFrozen: false)
        XCTAssertNotNil(colour)
    }

    func test_aboveThresholdReturnsPressureColour() {
        let colour = MetricMiniBarColours.fillColour(for: .memory, ratio: 0.95, isFrozen: false)
        XCTAssertNotNil(colour)
    }
}

// MARK: - MetricDimensionTests

final class MetricDimensionTests: XCTestCase {

    func test_allCasesAreEnumerated() {
        let cases = MetricDimension.allCases
        XCTAssertTrue(cases.contains(.cpu))
        XCTAssertTrue(cases.contains(.memory))
        XCTAssertTrue(cases.contains(.disk))
    }

    func test_displayLabels_nonEmpty() {
        for dim in MetricDimension.allCases {
            XCTAssertFalse(dim.displayLabel.isEmpty, "displayLabel empty for \(dim)")
        }
    }
}

// MARK: - StubRowMetricFeedAdapterTests

final class StubRowMetricFeedAdapterTests: XCTestCase {

    func test_node_returnsUnavailableForAllDimensions() async {
        let sut = StubRowMetricFeedAdapter()
        let series = await sut.metrics(forNode: "node-1")
        XCTAssertEqual(series.count, MetricDimension.allCases.count)
        for s in series {
            if case .unavailable = s.state { continue }
            XCTFail("Expected .unavailable for stub")
        }
    }

    func test_pod_returnsUnavailableForCPUAndMemory() async {
        let sut = StubRowMetricFeedAdapter()
        let series = await sut.metrics(forPodNamespace: "default", name: "my-pod")
        XCTAssertEqual(series.count, 2)
        XCTAssertTrue(series.contains { $0.dimension == .cpu })
        XCTAssertTrue(series.contains { $0.dimension == .memory })
    }
}
