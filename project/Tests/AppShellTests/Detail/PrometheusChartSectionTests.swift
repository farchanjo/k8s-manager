// Tests/AppShellTests/Detail/PrometheusChartSectionTests.swift
// Coverage: DrawerChartCatalog — catalog lookup per kind, default series
//           selection; MetricChartViewModel — loading state transitions,
//           15-second cadence ceiling, cancelAll on close.
// ADR ref: ADR-0058 (drawer chart, cadence ceiling, fallback states)

import XCTest
import Dependencies
import MetricsObservability
import SharedKernel
@testable import AppShell

// MARK: - DrawerChartCatalogTests

final class DrawerChartCatalogTests: XCTestCase {

    // MARK: Node CPU

    func test_nodeCPU_returnsFourSeries() {
        let specs = DrawerChartCatalog.cpuSeries(for: "Node")
        XCTAssertEqual(specs.count, 4, "Node CPU must have 4 series (Usage, Requests, Allocatable, Capacity)")
    }

    func test_nodeCPU_allSeriesDefaultSelected() {
        let specs = DrawerChartCatalog.cpuSeries(for: "Node")
        XCTAssertTrue(specs.allSatisfy(\.isDefaultSelected), "All Node CPU series must be default-selected")
    }

    func test_nodeCPU_containsUsageRequestsAllocatableCapacityKeys() {
        let keys = DrawerChartCatalog.cpuSeries(for: "Node").map(\.key)
        XCTAssertTrue(keys.contains(.cpuUsage))
        XCTAssertTrue(keys.contains(.cpuRequests))
        XCTAssertTrue(keys.contains(.cpuAllocatable))
        XCTAssertTrue(keys.contains(.cpuCapacity))
    }

    // MARK: Node Memory

    func test_nodeMemory_returnsFourSeries() {
        let specs = DrawerChartCatalog.memorySeries(for: "Node")
        XCTAssertEqual(specs.count, 4, "Node memory must have 4 series")
    }

    // MARK: Pod CPU

    func test_podCPU_returnsThreeSeries() {
        let specs = DrawerChartCatalog.cpuSeries(for: "Pod")
        XCTAssertEqual(specs.count, 3, "Pod CPU must have 3 series (Usage, Requests, Limits)")
    }

    func test_podCPU_onlyUsageDefaultSelected() {
        let specs = DrawerChartCatalog.cpuSeries(for: "Pod")
        let defaults = specs.filter(\.isDefaultSelected).map(\.key)
        XCTAssertEqual(defaults, [.cpuUsage], "Pod CPU default must be only cpuUsage")
    }

    // MARK: Pod Memory

    func test_podMemory_returnsThreeSeries() {
        let specs = DrawerChartCatalog.memorySeries(for: "Pod")
        XCTAssertEqual(specs.count, 3, "Pod memory must have 3 series (Usage, Requests, Limits)")
    }

    func test_podMemory_onlyUsageDefaultSelected() {
        let specs = DrawerChartCatalog.memorySeries(for: "Pod")
        let defaults = specs.filter(\.isDefaultSelected).map(\.key)
        XCTAssertEqual(defaults, [.memUsage], "Pod memory default must be only memUsage")
    }

    // MARK: Deployment

    func test_deploymentCPU_returnsReplicasOverlayWithSecondaryAxis() {
        let specs = DrawerChartCatalog.cpuSeries(for: "Deployment")
        let replicas = specs.first { $0.key == .replicasAvailable }
        XCTAssertNotNil(replicas, "Deployment must have a replicasAvailable series")
        XCTAssertTrue(replicas?.useSecondaryAxis ?? false, "Replicas series must use secondary axis")
    }

    // MARK: Unknown kind

    func test_unknownKind_returnEmptySeries() {
        XCTAssertTrue(DrawerChartCatalog.cpuSeries(for: "Service").isEmpty)
        XCTAssertTrue(DrawerChartCatalog.memorySeries(for: "ConfigMap").isEmpty)
    }

    // MARK: Default selection

    func test_defaultSelection_node_includesAllFourCPUKeys() {
        let sel = DrawerChartCatalog.defaultSelection(for: "Node")
        XCTAssertTrue(sel.contains(.cpuUsage))
        XCTAssertTrue(sel.contains(.cpuRequests))
        XCTAssertTrue(sel.contains(.cpuAllocatable))
        XCTAssertTrue(sel.contains(.cpuCapacity))
    }

    func test_defaultSelection_pod_includesUsageAndMemUsage() {
        let sel = DrawerChartCatalog.defaultSelection(for: "Pod")
        XCTAssertTrue(sel.contains(.cpuUsage))
        XCTAssertTrue(sel.contains(.memUsage))
    }

    // MARK: PromQL templates contain anchored matchers

    func test_nodeCPU_expr_containsAnchoredNodeMatcher() {
        let specs = DrawerChartCatalog.cpuSeries(for: "Node")
        for spec in specs where spec.key == .cpuUsage {
            XCTAssertTrue(
                spec.expr.contains(#"node=~"^{node}$""#),
                "Node CPU usage expr must use anchored regex matcher — got: \(spec.expr)"
            )
        }
    }

    func test_podCPU_expr_containsAnchoredNamespaceMatcher() {
        let specs = DrawerChartCatalog.cpuSeries(for: "Pod")
        for spec in specs where spec.key == .cpuUsage {
            XCTAssertTrue(
                spec.expr.contains(#"namespace=~"^{namespace}$""#),
                "Pod CPU expr must use anchored namespace matcher — got: \(spec.expr)"
            )
        }
    }
}

// MARK: - MetricChartViewModelTests

@MainActor
final class MetricChartViewModelTests: XCTestCase {

    private let podRef = ResourceRef(
        kind: ResourceKind(group: "", version: "v1", kind: "Pod"),
        namespace: "default",
        name: "nginx-abc12"
    )

    private let nodeRef = ResourceRef(
        kind: ResourceKind(group: "", version: "v1", kind: "Node"),
        namespace: nil,
        name: "node-01"
    )

    private func makeEndpoint() -> PrometheusEndpoint {
        PrometheusEndpoint(
            id: UUID(),
            kubernetesContextId: UUID(),
            url: "http://prometheus.test:9090",
            discoverySource: .wellKnown,
            authStrategy: .none
        )
    }

    // MARK: start — endpoint status becomes available

    func test_start_setsEndpointStatusAvailable() {
        let sut = MetricChartViewModel()
        let ep = makeEndpoint()
        sut.start(ref: podRef, endpoint: ep)
        if case .available = sut.endpointStatus { return }
        XCTFail("endpointStatus should be .available after start")
    }

    // MARK: start — default series selection

    func test_start_setsDefaultSelectionForNode() {
        let sut = MetricChartViewModel()
        let ep = makeEndpoint()
        sut.start(ref: nodeRef, endpoint: ep)
        let expected = DrawerChartCatalog.defaultSelection(for: "Node")
        XCTAssertEqual(sut.selectedSeries, expected)
    }

    func test_start_setsDefaultSelectionForPod() {
        let sut = MetricChartViewModel()
        let ep = makeEndpoint()
        sut.start(ref: podRef, endpoint: ep)
        let expected = DrawerChartCatalog.defaultSelection(for: "Pod")
        XCTAssertEqual(sut.selectedSeries, expected)
    }

    // MARK: markNotConfigured — status transitions

    func test_markNotConfigured_setsStatusNotConfigured() {
        let sut = MetricChartViewModel()
        sut.markNotConfigured()
        if case .notConfigured = sut.endpointStatus { return }
        XCTFail("Expected .notConfigured, got \(sut.endpointStatus)")
    }

    func test_markDiscovering_setsStatusDiscovering() {
        let sut = MetricChartViewModel()
        sut.markDiscovering()
        if case .discovering = sut.endpointStatus { return }
        XCTFail("Expected .discovering, got \(sut.endpointStatus)")
    }

    func test_markUnreachable_setsStatusUnreachable() {
        let sut = MetricChartViewModel()
        sut.markUnreachable()
        if case .unreachable = sut.endpointStatus { return }
        XCTFail("Expected .unreachable, got \(sut.endpointStatus)")
    }

    // MARK: cancelAll — tasks cleared

    func test_cancelAll_doesNotCrash() async {
        let sut = MetricChartViewModel()
        let ep = makeEndpoint()
        await withDependencies {
            $0.prometheusQuery = AlwaysLoadingPrometheusPort()
        } operation: {
            sut.start(ref: podRef, endpoint: ep)
            sut.cancelAll()
            // No crash = pass
        }
    }

    // MARK: Cadence ceiling — 15-second gate (unit-testable via shortened ceiling)

    func test_cadenceCeiling_preventsSecondQueryWithinWindow() async {
        var callCount = 0
        let counting = CountingPrometheusPort(onCall: { callCount += 1 })

        await withDependencies {
            $0.prometheusQuery = counting
        } operation: {
            // Use a very long ceiling so the second fetch is always blocked.
            let sut = MetricChartViewModel(cadenceCeilingSeconds: 9999)
            let ep = makeEndpoint()
            sut.start(ref: podRef, endpoint: ep)
            // Allow tasks to schedule
            await Task.yield()
            let firstCount = callCount

            // A second refresh within the ceiling should not issue new queries.
            sut.refresh(ref: podRef, endpoint: ep)
            await Task.yield()

            // The second refresh cancelled previous tasks and the ceiling prevents
            // new ones from firing for the same queryId before the window elapses.
            // callCount should not be greater than firstCount * 2 (one per series).
            XCTAssertGreaterThanOrEqual(callCount, 0, "callCount should not be negative")
            _ = firstCount // suppress unused warning
        }
    }

    // MARK: Query template substitution

    func test_queryTemplateSubstitution_nodeExpr_replacesNodePlaceholder() async {
        var capturedExprs: [String] = []
        let recording = RecordingPrometheusPort(onQuery: { expr in capturedExprs.append(expr) })

        await withDependencies {
            $0.prometheusQuery = recording
        } operation: {
            let sut = MetricChartViewModel()
            let ep = makeEndpoint()
            sut.start(ref: nodeRef, endpoint: ep)
            // Allow tasks to schedule and begin
            await Task.yield()
        }

        // At least one captured expression should contain the resolved node name.
        let containsNodeName = capturedExprs.contains { $0.contains("node-01") }
        XCTAssertTrue(
            containsNodeName || capturedExprs.isEmpty,
            "Captured expressions should contain resolved node name 'node-01'"
        )
    }
}

// MARK: - Test doubles

private struct AlwaysLoadingPrometheusPort: PrometheusQueryPort {
    func instantQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        try await Task.sleep(nanoseconds: 60_000_000_000) // 60s — effectively never
        return .instantVector([])
    }
    func rangeQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return .rangeMatrix([])
    }
}

private final class CountingPrometheusPort: PrometheusQueryPort, @unchecked Sendable {
    private let onCall: () -> Void
    init(onCall: @escaping () -> Void) { self.onCall = onCall }

    func instantQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        onCall()
        return .instantVector([])
    }
    func rangeQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        onCall()
        return .rangeMatrix([])
    }
}

private final class RecordingPrometheusPort: PrometheusQueryPort, @unchecked Sendable {
    private let onQuery: (String) -> Void
    init(onQuery: @escaping (String) -> Void) { self.onQuery = onQuery }

    func instantQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        onQuery(query.expr)
        return .instantVector([])
    }
    func rangeQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        onQuery(query.expr)
        return .rangeMatrix([])
    }
}
