// AnalyticsDashboardTests.swift — analytics_dashboard bounded context
// XCTest coverage: domain types, invariants, aggregate state transitions.

import XCTest
import Dependencies
@testable import AnalyticsDashboard

// MARK: - WidgetCodableRoundtripTests

final class WidgetCodableRoundtripTests: XCTestCase {

    // MARK: SparklineWidget

    func test_sparklineWidget_codable_roundtrip() throws {
        let widget = AnalyticsWidget.sparkline(SparklineWidget(
            widgetId: "cluster-cpu-sparkline",
            title: "Cluster CPU",
            promQLTemplate: "rate(container_cpu_usage_seconds_total[5m])",
            rangeMinutes: 60,
            unit: .cores
        ))
        let data = try JSONEncoder().encode(widget)
        let decoded = try JSONDecoder().decode(AnalyticsWidget.self, from: data)
        XCTAssertEqual(widget, decoded)
        XCTAssertEqual(widget.widgetId, "cluster-cpu-sparkline")
    }

    // MARK: HeatmapWidget

    func test_heatmapWidget_percentilesShown_always_50_95_99() throws {
        let widget = HeatmapWidget(
            widgetId: "svc-latency-heatmap",
            title: "Request Latency",
            bucketsQuery: "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))",
            rangeMinutes: 60
        )
        // Spec invariant §5: heatmap always displays [50, 95, 99]
        XCTAssertEqual(widget.percentilesShown, [50, 95, 99])

        let wrapped = AnalyticsWidget.heatmap(widget)
        let data = try JSONEncoder().encode(wrapped)
        let decoded = try JSONDecoder().decode(AnalyticsWidget.self, from: data)
        XCTAssertEqual(wrapped, decoded)

        if case .heatmap(let hw) = decoded {
            XCTAssertEqual(hw.percentilesShown, [50, 95, 99])
        } else {
            XCTFail("Expected .heatmap variant")
        }
    }

    // MARK: All widget kinds round-trip

    func test_all_widget_kinds_roundtrip() throws {
        let widgets: [AnalyticsWidget] = [
            .sparkline(SparklineWidget(widgetId: "w1", title: "T", promQLTemplate: "up", unit: .count)),
            .lineChart(LineChartWidget(widgetId: "w2", title: "T", series: [
                SeriesQuery(label: "CPU", promQLTemplate: "rate(cpu[5m])", color: .healthy)
            ], rangeMinutes: 30)),
            .heatmap(HeatmapWidget(widgetId: "w3", title: "T", bucketsQuery: "hist", rangeMinutes: 60)),
            .stackedBar(StackedBarWidget(widgetId: "w4", title: "T", segments: [
                Segment(label: "Running", query: "pods_running", color: .healthy),
                Segment(label: "Failed", query: "pods_failed", color: .error)
            ])),
            .count(CountWidget(widgetId: "w5", title: "T", query: "sum(up)")),
            .topList(TopListWidget(widgetId: "w6", title: "T", query: "topk(5,up)")),
            .eventTimeline(EventTimelineWidget(widgetId: "w7", title: "T",
                sourceFilter: .all, rangeMinutes: 60)),
            .topologyGraph(TopologyGraphWidget(widgetId: "w8", title: "T",
                rootRef: ResourceRef(apiVersion: "apps/v1", kind: "Deployment", name: "nginx"))),
            .logErrorRate(LogErrorRateWidget(widgetId: "w9", title: "T",
                namespace: "default", podSelector: "app=nginx")),
            .diffViewer(DiffViewerWidget(widgetId: "w10", title: "T",
                leftRef: ResourceRef(apiVersion: "v1", kind: "ConfigMap", name: "cm-v1"),
                rightRef: ResourceRef(apiVersion: "v1", kind: "ConfigMap", name: "cm-v2"))),
            .conditionsList(ConditionsListWidget(widgetId: "w11", title: "T",
                resourceRef: ResourceRef(apiVersion: "apps/v1", kind: "Deployment", name: "nginx"))),
        ]

        for widget in widgets {
            let data = try JSONEncoder().encode(widget)
            let decoded = try JSONDecoder().decode(AnalyticsWidget.self, from: data)
            XCTAssertEqual(widget, decoded, "Round-trip failed for widgetId: \(widget.widgetId)")
        }
    }
}

// MARK: - ScopePresetTests

final class ScopePresetTests: XCTestCase {

    func test_all_presets_have_unique_presetIds() {
        let ids = ScopePreset.all.map(\.presetId)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate preset IDs found")
    }

    func test_all_preset_layouts_are_non_empty() {
        for preset in ScopePreset.all {
            XCTAssertFalse(preset.defaultLayout.isEmpty, "Empty layout for preset \(preset.presetId)")
        }
    }

    func test_all_preset_grid_slots_satisfy_column_constraint() {
        for preset in ScopePreset.all {
            for slot in preset.defaultLayout {
                XCTAssertTrue(
                    slot.position.isWithinGridBounds,
                    "Grid violation in preset '\(preset.presetId)' widgetId '\(slot.widgetId)': col=\(slot.position.col) colSpan=\(slot.position.colSpan)"
                )
            }
        }
    }

    func test_preset_lookup_by_scope_returns_matching_preset() {
        let scope = DashboardScope.namespaceDetail(namespace: "kube-system")
        let preset = ScopePreset.preset(for: scope)
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.presetId, "namespace_detail")
    }

    func test_preset_lookup_covers_all_nine_scope_kinds() {
        let scopes: [DashboardScope] = [
            .clusterOverview,
            .namespaceDetail(namespace: "default"),
            .podDetail(namespace: "default", podName: "nginx-abc"),
            .nodeDetail(nodeName: "node-1"),
            .workloadDetail(kind: .deployment, namespace: "default", name: "nginx"),
            .serviceDetail(namespace: "default", name: "svc"),
            .helmReleaseDetail(namespace: "default", releaseName: "my-chart", revision: 2),
            .debugTimeline(timeRangeMinutes: .oneHour),
            .topologyGraph(rootSelector: nil),
        ]
        for scope in scopes {
            XCTAssertNotNil(ScopePreset.preset(for: scope), "No preset for scope \(scope.presetId)")
        }
    }

    func test_scopePreset_codable_roundtrip() throws {
        let preset = ScopePreset.clusterOverview
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(ScopePreset.self, from: data)
        XCTAssertEqual(preset.presetId, decoded.presetId)
        XCTAssertEqual(preset.defaultLayout.count, decoded.defaultLayout.count)
    }
}

// MARK: - DashboardAggregateTests

final class DashboardAggregateTests: XCTestCase {

    private func makeDashboard(
        scope: DashboardScope = .clusterOverview,
        layout: [WidgetSlot] = []
    ) -> Dashboard {
        Dashboard(
            id: UUID().uuidString,
            scope: scope,
            kubernetesContextId: UUID().uuidString,
            layout: layout,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z"
        )
    }

    func test_aggregate_initial_state_is_not_customised() async {
        let aggregate = DashboardAggregate(dashboard: makeDashboard())
        let customised = await aggregate.isCustomised()
        XCTAssertFalse(customised)
    }

    func test_applyOperatorLayout_sets_customised_flag() async throws {
        let aggregate = DashboardAggregate(dashboard: makeDashboard())
        let slots = [
            WidgetSlot(widgetId: "w1", position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 6)),
            WidgetSlot(widgetId: "w2", position: GridPosition(row: 0, col: 6, rowSpan: 1, colSpan: 6)),
        ]
        try await aggregate.applyOperatorLayout(slots, updatedAt: "2026-01-02T00:00:00Z")
        let dashboard = await aggregate.dashboard
        XCTAssertTrue(dashboard.customisedByOperator)
        XCTAssertEqual(dashboard.layout.count, 2)
        XCTAssertEqual(dashboard.updatedAt, "2026-01-02T00:00:00Z")
    }

    func test_applyOperatorLayout_rejects_grid_violation() async {
        let aggregate = DashboardAggregate(dashboard: makeDashboard())
        // col=8, colSpan=6 => 8+6=14 > 12 — must throw
        let badSlot = WidgetSlot(
            widgetId: "overflow",
            position: GridPosition(row: 0, col: 8, rowSpan: 1, colSpan: 6)
        )
        do {
            try await aggregate.applyOperatorLayout([badSlot], updatedAt: "now")
            XCTFail("Expected gridConstraintViolation error")
        } catch DashboardAggregateError.gridConstraintViolation(let widgetId, _, _) {
            XCTAssertEqual(widgetId, "overflow")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_resetToPreset_clears_customised_flag() async throws {
        let aggregate = DashboardAggregate(dashboard: makeDashboard())
        // First customise
        let customSlots = [
            WidgetSlot(widgetId: "custom", position: GridPosition(row: 0, col: 0, rowSpan: 1, colSpan: 12))
        ]
        try await aggregate.applyOperatorLayout(customSlots, updatedAt: "2026-01-02T00:00:00Z")
        XCTAssertTrue(await aggregate.isCustomised())

        // Reset to preset layout
        let presetSlots = ScopePreset.clusterOverview.defaultLayout
        try await aggregate.resetToPreset(presetSlots, updatedAt: "2026-01-03T00:00:00Z")
        let dashboard = await aggregate.dashboard
        XCTAssertFalse(dashboard.customisedByOperator)
        XCTAssertEqual(dashboard.layout.count, presetSlots.count)
    }

    func test_applyRefreshInterval_updates_interval() async {
        let aggregate = DashboardAggregate(dashboard: makeDashboard())
        await aggregate.applyRefreshInterval(.sixtySeconds, updatedAt: "2026-01-02T00:00:00Z")
        let dashboard = await aggregate.dashboard
        XCTAssertEqual(dashboard.refreshInterval, .sixtySeconds)
    }
}

// MARK: - WidgetBudgetTests

final class WidgetBudgetTests: XCTestCase {

    func test_default_budget_has_canonical_values() {
        let budget = WidgetBudget.default
        XCTAssertEqual(budget.maxPrometheusQueriesPerCycle, 5)
        XCTAssertEqual(budget.maxSimultaneousQueries, 8)
        XCTAssertEqual(budget.refreshIntervalSeconds, 30)
        XCTAssertTrue(budget.coalescingEnabled)
    }

    func test_budget_rejects_maxQueries_out_of_range() {
        XCTAssertThrowsError(try WidgetBudget(
            maxPrometheusQueriesPerCycle: 6,
            maxSimultaneousQueries: 8,
            refreshIntervalSeconds: 30,
            coalescingEnabled: true
        )) { error in
            if case WidgetBudget.ValidationError.maxQueriesOutOfRange(let v) = error {
                XCTAssertEqual(v, 6)
            } else {
                XCTFail("Expected maxQueriesOutOfRange, got \(error)")
            }
        }
    }

    func test_budget_rejects_coalescing_disabled() {
        XCTAssertThrowsError(try WidgetBudget(
            maxPrometheusQueriesPerCycle: 5,
            maxSimultaneousQueries: 8,
            refreshIntervalSeconds: 30,
            coalescingEnabled: false
        )) { error in
            guard case WidgetBudget.ValidationError.coalescingMustBeEnabled = error else {
                XCTFail("Expected coalescingMustBeEnabled, got \(error)")
                return
            }
        }
    }

    func test_budget_rejects_refresh_interval_below_5() {
        XCTAssertThrowsError(try WidgetBudget(
            maxPrometheusQueriesPerCycle: 5,
            maxSimultaneousQueries: 8,
            refreshIntervalSeconds: 4,
            coalescingEnabled: true
        )) { error in
            guard case WidgetBudget.ValidationError.refreshIntervalOutOfRange = error else {
                XCTFail("Expected refreshIntervalOutOfRange, got \(error)")
                return
            }
        }
    }

    func test_lowPower_budget_uses_60s_interval() {
        XCTAssertEqual(WidgetBudget.lowPower.refreshIntervalSeconds, 60)
    }
}

// MARK: - WidgetQueryDispatchServiceTests

final class WidgetQueryDispatchServiceTests: XCTestCase {

    func test_budget_exhaustion_throws_after_max_queries() async throws {
        let budget = WidgetBudget.unchecked(maxPrometheusQueriesPerCycle: 2)
        let service = WidgetQueryDispatchService(budget: budget)
        let scopeParams = ScopeParameters(namespace: "default")
        let contextId = UUID().uuidString
        let fakePort = FakeMetricsQueryPort()

        try await withDependencies {
            $0.analyticsMetricsQuery = fakePort
        } operation: {
            // First two queries succeed
            _ = try await service.rangeQuery(
                promQLTemplate: "rate(cpu[5m])",
                rangeMinutes: 60,
                scopeParams: scopeParams,
                kubernetesContextId: contextId
            )
            _ = try await service.rangeQuery(
                promQLTemplate: "rate(mem[5m])",
                rangeMinutes: 60,
                scopeParams: scopeParams,
                kubernetesContextId: contextId
            )
            // Third distinct query must exhaust the budget
            do {
                _ = try await service.rangeQuery(
                    promQLTemplate: "rate(net[5m])",
                    rangeMinutes: 60,
                    scopeParams: scopeParams,
                    kubernetesContextId: contextId
                )
                XCTFail("Expected BudgetExhaustedError")
            } catch is BudgetExhaustedError {
                // Expected
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_coalescing_reuses_result_for_identical_query() async throws {
        let service = WidgetQueryDispatchService(budget: .default)
        let scopeParams = ScopeParameters(namespace: "monitoring")
        let contextId = UUID().uuidString
        let fakePort = CountingMetricsQueryPort()

        try await withDependencies {
            $0.analyticsMetricsQuery = fakePort
        } operation: {
            let template = "rate(http_requests_total{namespace=\"{namespace}\"}[5m])"
            // Issue same query twice
            _ = try await service.rangeQuery(
                promQLTemplate: template,
                rangeMinutes: 30,
                scopeParams: scopeParams,
                kubernetesContextId: contextId
            )
            _ = try await service.rangeQuery(
                promQLTemplate: template,
                rangeMinutes: 30,
                scopeParams: scopeParams,
                kubernetesContextId: contextId
            )
            let usedCount = await service.queriesUsedThisCycle()
            // Both calls shared same resolved key — only 1 upstream call
            XCTAssertEqual(usedCount, 1, "Coalescing should reduce two identical queries to one")
        }
    }

    func test_resetCycle_clears_counters_and_cache() async throws {
        let service = WidgetQueryDispatchService(budget: .default)
        let fakePort = FakeMetricsQueryPort()

        try await withDependencies {
            $0.analyticsMetricsQuery = fakePort
        } operation: {
            _ = try await service.rangeQuery(
                promQLTemplate: "up",
                rangeMinutes: 60,
                scopeParams: ScopeParameters(),
                kubernetesContextId: "ctx-1"
            )
            let beforeReset = await service.queriesUsedThisCycle()
            XCTAssertEqual(beforeReset, 1)

            await service.resetCycle()

            let afterReset = await service.queriesUsedThisCycle()
            XCTAssertEqual(afterReset, 0)
        }
    }
}

// MARK: - DrillDownEventTests

final class DrillDownEventTests: XCTestCase {

    func test_drillToScope_codable_roundtrip() throws {
        let event = DrillDownEvent.drillToScope(DrillToScope(
            sourceDashboardId: "dash-1",
            sourceWidgetId: "w-1",
            targetScope: .namespaceDetail(namespace: "kube-system")
        ))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(DrillDownEvent.self, from: data)
        XCTAssertEqual(event, decoded)
        XCTAssertEqual(event.sourceDashboardId, "dash-1")
        XCTAssertEqual(event.sourceWidgetId, "w-1")
    }

    func test_drillToLogs_carries_click_timestamp() throws {
        let ts = "2026-05-15T11:05:00Z"
        let log = DrillToLogs(
            sourceDashboardId: "dash-1",
            sourceWidgetId: "heatmap-1",
            namespace: "default",
            podName: "app=nginx",
            timestampRFC3339: ts
        )
        XCTAssertEqual(log.timestampRFC3339, ts)

        let event = DrillDownEvent.drillToLogs(log)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(DrillDownEvent.self, from: data)
        XCTAssertEqual(event, decoded)
    }

    func test_drillToEvents_default_timeRange_is_oneHour() {
        let event = DrillToEvents(
            sourceDashboardId: "dash-1",
            sourceWidgetId: "w-1",
            resourceRef: ResourceRef(apiVersion: "apps/v1", kind: "Deployment", name: "nginx")
        )
        XCTAssertEqual(event.timeRangeMinutes, .oneHour)
        XCTAssertEqual(event.timeRangeMinutes.rawValue, 60)
    }
}

// MARK: - Test Doubles

private struct FakeMetricsQueryPort: MetricsQueryPort {
    func instantQuery(promQL _: String, kubernetesContextId _: String) async throws -> [InstantSample] {
        [InstantSample(labels: ["__name__": "up"], tUnix: 0, value: 1.0)]
    }

    func rangeQuery(
        promQL _: String,
        rangeMinutes _: Int,
        kubernetesContextId _: String
    ) async throws -> [MetricSeries] {
        [MetricSeries(labels: ["__name__": "up"], points: [MetricDataPoint(tUnix: 0, value: 1.0)])]
    }
}

/// Counts how many distinct upstream requests were made (to verify coalescing).
private actor CountingMetricsQueryPort: MetricsQueryPort {
    private(set) var rangeCallCount = 0

    func instantQuery(promQL _: String, kubernetesContextId _: String) async throws -> [InstantSample] {
        []
    }

    func rangeQuery(
        promQL _: String,
        rangeMinutes _: Int,
        kubernetesContextId _: String
    ) async throws -> [MetricSeries] {
        rangeCallCount += 1
        return []
    }
}
