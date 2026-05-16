// MetricsObservabilityTests.swift — metrics_observability bounded context
// XCTest coverage: domain types, invariants, DI port overrides.

import XCTest
import Dependencies
@testable import MetricsObservability

// MARK: - PromQueryTests

final class PromQueryTests: XCTestCase {
    func test_instantQuery_factory_sets_instant_true() {
        let q = PromQuery.instant(expr: "up")
        XCTAssertTrue(q.instant)
        XCTAssertNil(q.range)
        XCTAssertEqual(q.expr, "up")
    }

    func test_rangeQuery_factory_sets_instant_false() {
        let range = TimeRange(start: "now-60m", end: "now", stepSeconds: 30)
        let q = PromQuery.range(expr: "up", range: range)
        XCTAssertFalse(q.instant)
        XCTAssertNotNil(q.range)
        XCTAssertEqual(q.range?.stepSeconds, 30)
    }

    func test_rangeQuery_codable_roundtrip() throws {
        let range = TimeRange(start: "2024-01-01T00:00:00Z", end: "2024-01-01T01:00:00Z", stepSeconds: 60)
        let q = PromQuery.range(expr: "rate(up[5m])", range: range)
        let data = try JSONEncoder().encode(q)
        let decoded = try JSONDecoder().decode(PromQuery.self, from: data)
        XCTAssertEqual(q, decoded)
    }

    func test_instantQuery_with_labelSelector_roundtrips() throws {
        let q = PromQuery.instant(expr: "up", labelSelector: ["namespace": "default", "app": "nginx"])
        let data = try JSONEncoder().encode(q)
        let decoded = try JSONDecoder().decode(PromQuery.self, from: data)
        XCTAssertEqual(decoded.labelSelector, ["namespace": "default", "app": "nginx"])
    }

    func test_timeRange_stepSeconds_minimum_one() {
        let range = TimeRange(start: "now-5m", end: "now", stepSeconds: 1)
        XCTAssertEqual(range.stepSeconds, 1)
    }
}

// MARK: - PrometheusEndpointTests

final class PrometheusEndpointTests: XCTestCase {
    private func makeEndpoint(
        status: EndpointStatus = .unknown,
        authStrategy: AuthStrategy = .none,
        discoverySource: DiscoverySource = .wellKnown
    ) -> PrometheusEndpoint {
        PrometheusEndpoint(
            id: UUID(),
            kubernetesContextId: UUID(),
            url: "http://prometheus-operated.monitoring.svc:9090",
            discoverySource: discoverySource,
            authStrategy: authStrategy,
            status: status
        )
    }

    func test_default_insecureSkipTLSVerify_is_false() {
        let ep = makeEndpoint()
        XCTAssertFalse(ep.insecureSkipTLSVerify)
    }

    func test_default_status_is_unknown() {
        let ep = makeEndpoint()
        XCTAssertEqual(ep.status, .unknown)
    }

    func test_probedWith_returns_updated_copy() {
        let ep = makeEndpoint()
        let probed = ep.probedWith(status: .healthy, probedAt: "2024-01-01T00:00:00Z", version: "3.7.1")
        XCTAssertEqual(probed.status, .healthy)
        XCTAssertEqual(probed.lastProbedAt, "2024-01-01T00:00:00Z")
        XCTAssertEqual(probed.version, "3.7.1")
        // Identity fields unchanged
        XCTAssertEqual(probed.id, ep.id)
        XCTAssertEqual(probed.url, ep.url)
    }

    func test_probedWith_does_not_clear_existing_version_when_nil_passed() {
        var ep = makeEndpoint()
        ep = ep.probedWith(status: .healthy, probedAt: "2024-01-01T00:00:00Z", version: "3.7.0")
        let updated = ep.probedWith(status: .unreachable, probedAt: "2024-01-01T01:00:00Z", version: nil)
        XCTAssertEqual(updated.version, "3.7.0")
    }

    func test_all_discoverySource_cases_codable() throws {
        for source in DiscoverySource.allCases {
            let ep = PrometheusEndpoint(
                id: UUID(), kubernetesContextId: UUID(),
                url: "http://prometheus:9090", discoverySource: source,
                authStrategy: .none
            )
            let data = try JSONEncoder().encode(ep)
            let decoded = try JSONDecoder().decode(PrometheusEndpoint.self, from: data)
            XCTAssertEqual(decoded.discoverySource, source)
        }
    }

    func test_all_authStrategy_cases_codable() throws {
        let strategies: [AuthStrategy] = [
            .none,
            .bearerInherit,
            .bearer(token: "test-token"),
            .basic(username: "admin", password: "secret"),
        ]
        for strategy in strategies {
            let ep = makeEndpoint(authStrategy: strategy)
            let data = try JSONEncoder().encode(ep)
            let decoded = try JSONDecoder().decode(PrometheusEndpoint.self, from: data)
            XCTAssertEqual(decoded.authStrategy, strategy)
        }
    }

    func test_all_endpointStatus_cases_codable() throws {
        for status in EndpointStatus.allCases {
            let ep = makeEndpoint(status: status)
            let data = try JSONEncoder().encode(ep)
            let decoded = try JSONDecoder().decode(PrometheusEndpoint.self, from: data)
            XCTAssertEqual(decoded.status, status)
        }
    }

    func test_discoverySource_precedence_order() {
        // manual_override (index 0) must sort before well_known (index 1)
        XCTAssertLessThan(
            DiscoverySource.allCases.firstIndex(of: .manualOverride)!,
            DiscoverySource.allCases.firstIndex(of: .wellKnown)!
        )
    }
}

// MARK: - CuratedQueryCatalogTests

final class CuratedQueryCatalogTests: XCTestCase {
    func test_catalog_contains_exactly_12_entries() {
        XCTAssertEqual(CuratedQueryCatalog.all.count, 12)
    }

    func test_catalog_ids_are_unique() {
        let ids = CuratedQueryCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func test_catalog_all_steps_at_least_one() {
        for entry in CuratedQueryCatalog.all {
            XCTAssertGreaterThanOrEqual(entry.defaultStepSeconds, 1, "Failed for \(entry.id)")
            XCTAssertGreaterThanOrEqual(entry.defaultRange.stepSeconds, 1, "Failed for \(entry.id)")
        }
    }

    func test_catalog_covers_all_categories() {
        let categories = Set(CuratedQueryCatalog.all.map(\.category))
        XCTAssertEqual(categories, Set(QueryCategory.allCases))
    }

    func test_catalog_all_exprs_non_empty() {
        for entry in CuratedQueryCatalog.all {
            XCTAssertFalse(entry.expr.isEmpty, "expr empty for \(entry.id)")
        }
    }

    func test_known_entry_pod_cpu_usage_seconds() {
        let entry = CuratedQueryCatalog.all.first { $0.id == "pod_cpu_usage_seconds" }
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.category, .cpu)
        XCTAssertTrue(entry?.expr.contains("{namespace}") == true)
        XCTAssertTrue(entry?.expr.contains("{podName}") == true)
    }

    func test_catalog_codable_roundtrip() throws {
        let entry = CuratedQueryCatalog.all[0]
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CuratedQuery.self, from: data)
        XCTAssertEqual(entry, decoded)
    }
}

// MARK: - TimeSeriesTests

final class TimeSeriesTests: XCTestCase {
    private func makePoints(count: Int) -> [DataPoint] {
        (0..<count).map { DataPoint(tUnix: Double($0), value: Double($0) * 0.1) }
    }

    func test_downsampled_noops_when_count_lte_target() {
        let series = TimeSeries(metric: ["__name__": "up"], points: makePoints(count: 100))
        let result = series.downsampled(to: 200)
        XCTAssertEqual(result.points.count, 100)
    }

    func test_downsampled_reduces_to_target() {
        let series = TimeSeries(metric: ["__name__": "up"], points: makePoints(count: 500))
        let result = series.downsampled(to: 200)
        XCTAssertEqual(result.points.count, 200)
    }

    func test_downsampled_preserves_first_and_last_point() {
        let points = makePoints(count: 400)
        let series = TimeSeries(metric: [:], points: points)
        let result = series.downsampled(to: 200)
        XCTAssertEqual(result.points.first?.tUnix, points.first?.tUnix)
        XCTAssertEqual(result.points.last?.tUnix, points.last?.tUnix)
    }

    func test_downsampled_preserves_metric_labels() {
        let labels = ["namespace": "default", "pod": "nginx-abc"]
        let series = TimeSeries(metric: labels, points: makePoints(count: 300))
        XCTAssertEqual(series.downsampled(to: 200).metric, labels)
    }

    func test_invariant_200_point_cap() {
        // Invariant from ADR-0016: series > 200 pts must be downsampled
        let large = TimeSeries(metric: [:], points: makePoints(count: 201))
        let downsampled = large.downsampled()
        XCTAssertLessThanOrEqual(downsampled.points.count, 200)
    }

    func test_metricSample_codable_roundtrip() throws {
        let sample = MetricSample(
            metric: ["__name__": "up", "job": "kubernetes-apiservers"],
            timestampUnix: 1_700_000_000.5,
            value: 1.0
        )
        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(MetricSample.self, from: data)
        XCTAssertEqual(sample, decoded)
    }
}

// MARK: - PromQueryResultTests

final class PromQueryResultTests: XCTestCase {
    func test_instantVector_carries_samples() {
        let samples = [MetricSample(metric: [:], timestampUnix: 0, value: 1.0)]
        let result = PromQueryResult.instantVector(samples)
        if case .instantVector(let s) = result {
            XCTAssertEqual(s.count, 1)
        } else {
            XCTFail("Expected .instantVector")
        }
    }

    func test_rangeMatrix_carries_series() {
        let series = [TimeSeries(metric: [:], points: [])]
        let result = PromQueryResult.rangeMatrix(series)
        if case .rangeMatrix(let s) = result {
            XCTAssertEqual(s.count, 1)
        } else {
            XCTFail("Expected .rangeMatrix")
        }
    }

    func test_scalar_carries_value() {
        let result = PromQueryResult.scalar(timestampUnix: 1_700_000_000.0, value: 42.0)
        if case .scalar(_, let v) = result {
            XCTAssertEqual(v, 42.0)
        } else {
            XCTFail("Expected .scalar")
        }
    }
}

// MARK: - PrometheusQueryPortDITests

final class PrometheusQueryPortDITests: XCTestCase {
    func test_portCanBeOverridden_viaDependencies() async throws {
        let fake = FakePrometheusQueryPort()

        try await withDependencies {
            $0.prometheusQuery = fake
        } operation: {
            @Dependency(\.prometheusQuery) var port
            let ep = PrometheusEndpoint(
                id: UUID(), kubernetesContextId: UUID(),
                url: "http://prometheus:9090",
                discoverySource: .wellKnown, authStrategy: .none
            )
            let result = try await port.instantQuery(.instant(expr: "up"), endpoint: ep)
            if case .instantVector(let samples) = result {
                XCTAssertEqual(samples.count, 1)
            } else {
                XCTFail("Expected .instantVector from fake port")
            }
        }
    }

    func test_unimplemented_port_throws_unimplemented() async {
        let port = UnimplementedPrometheusQueryPort()
        let ep = PrometheusEndpoint(
            id: UUID(), kubernetesContextId: UUID(),
            url: "http://prometheus:9090",
            discoverySource: .wellKnown, authStrategy: .none
        )
        do {
            _ = try await port.instantQuery(.instant(expr: "up"), endpoint: ep)
            XCTFail("Expected PrometheusQueryError.unimplemented")
        } catch PrometheusQueryError.unimplemented {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - EndpointDiscoveryPortDITests

final class EndpointDiscoveryPortDITests: XCTestCase {
    func test_portCanBeOverridden_viaDependencies() async throws {
        let contextId = UUID()
        let fake = FakeEndpointDiscoveryPort(kubernetesContextId: contextId)

        try await withDependencies {
            $0.endpointDiscovery = fake
        } operation: {
            @Dependency(\.endpointDiscovery) var port
            let candidates = try await port.discover(kubernetesContextId: contextId)
            XCTAssertEqual(candidates.count, 1)
            XCTAssertEqual(candidates[0].discoverySource, .wellKnown)
        }
    }

    func test_unimplemented_discovery_throws_unimplemented() async {
        let port = UnimplementedEndpointDiscoveryPort()
        do {
            _ = try await port.discover(kubernetesContextId: UUID())
            XCTFail("Expected EndpointDiscoveryError.unimplemented")
        } catch EndpointDiscoveryError.unimplemented {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_unimplemented_probe_throws_unimplemented() async {
        let port = UnimplementedEndpointDiscoveryPort()
        let ep = PrometheusEndpoint(
            id: UUID(), kubernetesContextId: UUID(),
            url: "http://prometheus:9090",
            discoverySource: .wellKnown, authStrategy: .none
        )
        do {
            _ = try await port.probe(ep)
            XCTFail("Expected EndpointDiscoveryError.unimplemented")
        } catch EndpointDiscoveryError.unimplemented {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Test Doubles

private struct FakePrometheusQueryPort: PrometheusQueryPort {
    func instantQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        .instantVector([MetricSample(metric: ["__name__": "up"], timestampUnix: 0, value: 1.0)])
    }

    func rangeQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        .rangeMatrix([])
    }
}

private struct FakeEndpointDiscoveryPort: EndpointDiscoveryPort {
    let kubernetesContextId: UUID

    func discover(kubernetesContextId: UUID) async throws -> [PrometheusEndpoint] {
        [PrometheusEndpoint(
            id: UUID(),
            kubernetesContextId: kubernetesContextId,
            url: "http://prometheus-operated.monitoring.svc:9090",
            discoverySource: .wellKnown,
            authStrategy: .none
        )]
    }

    func probe(_ endpoint: PrometheusEndpoint) async throws -> PrometheusEndpoint {
        endpoint.probedWith(status: .healthy, probedAt: "2024-01-01T00:00:00Z", version: "3.7.1")
    }
}
