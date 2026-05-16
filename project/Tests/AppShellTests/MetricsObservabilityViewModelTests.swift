// Tests/AppShellTests/MetricsObservabilityViewModelTests.swift
// Coverage: MetricsObservabilityViewModel endpoint discovery + curated query flows.

import XCTest
import Dependencies
import ConcurrencyExtras
@testable import AppShell
import MetricsObservability

// MARK: - MetricsObservabilityViewModelTests

@MainActor
final class MetricsObservabilityViewModelTests: XCTestCase {

    // MARK: Initial state

    func test_initialState_isIdle() {
        let sut = MetricsObservabilityViewModel()
        XCTAssertTrue(sut.endpoints.isIdle)
        XCTAssertTrue(sut.queryResults.isEmpty)
        XCTAssertEqual(sut.selectedQuery?.id, CuratedQueryCatalog.all.first?.id)
    }

    // MARK: discoverEndpoints

    func test_discoverEndpoints_setsEndpointsOnSuccess() async {
        let expected = [makeEndpoint(status: .healthy), makeEndpoint(status: .unknown)]
        let fakeDiscovery = FakeEndpointDiscovery(endpoints: expected)

        await withDependencies {
            $0.endpointDiscovery = fakeDiscovery
        } operation: {
            let sut = MetricsObservabilityViewModel()
            await sut.discoverEndpoints()
            XCTAssertEqual(sut.endpoints.value?.count, 2)
            XCTAssertNil(sut.endpoints.error)
        }
    }

    func test_discoverEndpoints_setsFailureOnError() async {
        let fakeDiscovery = FakeEndpointDiscovery(
            error: EndpointDiscoveryError.kubernetesApiUnavailable(detail: "no server")
        )

        await withDependencies {
            $0.endpointDiscovery = fakeDiscovery
        } operation: {
            let sut = MetricsObservabilityViewModel()
            await sut.discoverEndpoints()
            XCTAssertNil(sut.endpoints.value)
            XCTAssertNotNil(sut.endpoints.error)
        }
    }

    // MARK: runCuratedQuery

    func test_runCuratedQuery_storesSuccessResult() async {
        let query = CuratedQueryCatalog.all[0]
        let stubResult = PromQueryResult.scalar(timestampUnix: 1_000, value: 0.42)
        let fakeDiscovery = FakeEndpointDiscovery(endpoints: [makeEndpoint(status: .healthy)])
        let fakeQuery = FakePrometheusQuery(result: stubResult)

        await withDependencies {
            $0.endpointDiscovery = fakeDiscovery
            $0.prometheusQuery = fakeQuery
        } operation: {
            let sut = MetricsObservabilityViewModel()
            await sut.discoverEndpoints()
            await sut.runCuratedQuery(query)
            let resource = sut.queryResults[query.id]
            XCTAssertNotNil(resource?.value)
            XCTAssertNil(resource?.error)
        }
    }

    func test_runCuratedQuery_setsFailureWhenNoEndpoints() async {
        let query = CuratedQueryCatalog.all[0]
        let fakeDiscovery = FakeEndpointDiscovery(endpoints: [])
        let fakeQuery = FakePrometheusQuery(result: .scalar(timestampUnix: 0, value: 0))

        await withDependencies {
            $0.endpointDiscovery = fakeDiscovery
            $0.prometheusQuery = fakeQuery
        } operation: {
            let sut = MetricsObservabilityViewModel()
            await sut.discoverEndpoints()   // success with empty list
            await sut.runCuratedQuery(query)
            XCTAssertNotNil(sut.queryResults[query.id]?.error)
        }
    }

    func test_runCuratedQuery_prefersHealthyEndpoint() async {
        let degraded = makeEndpoint(status: .unauthorized)
        let healthy = makeEndpoint(status: .healthy)
        let capturedEndpoint = LockIsolated<PrometheusEndpoint?>(nil)
        let fakeDiscovery = FakeEndpointDiscovery(endpoints: [degraded, healthy])
        let fakeQuery = FakePrometheusQuery(result: .scalar(timestampUnix: 0, value: 1)) {
            capturedEndpoint.setValue($0)
        }
        let query = CuratedQueryCatalog.all[0]

        await withDependencies {
            $0.endpointDiscovery = fakeDiscovery
            $0.prometheusQuery = fakeQuery
        } operation: {
            let sut = MetricsObservabilityViewModel()
            await sut.discoverEndpoints()
            await sut.runCuratedQuery(query)
            XCTAssertEqual(capturedEndpoint.value?.status, .healthy)
        }
    }
}

// MARK: - Test doubles

private func makeEndpoint(status: EndpointStatus) -> PrometheusEndpoint {
    PrometheusEndpoint(
        id: UUID(),
        kubernetesContextId: UUID(),
        url: "http://prometheus.example.com:9090",
        discoverySource: .wellKnown,
        authStrategy: .none,
        status: status
    )
}

private struct FakeEndpointDiscovery: EndpointDiscoveryPort {
    let stubbedEndpoints: [PrometheusEndpoint]
    let stubbedError: Error?

    init(endpoints: [PrometheusEndpoint] = [], error: Error? = nil) {
        self.stubbedEndpoints = endpoints
        self.stubbedError = error
    }

    func discover(kubernetesContextId: UUID) async throws -> [PrometheusEndpoint] {
        if let error = stubbedError { throw error }
        return stubbedEndpoints
    }

    func probe(_ endpoint: PrometheusEndpoint) async throws -> PrometheusEndpoint {
        endpoint
    }
}

private struct FakePrometheusQuery: PrometheusQueryPort {
    let stubbedResult: PromQueryResult
    let onCall: (@Sendable (PrometheusEndpoint) -> Void)?

    init(result: PromQueryResult, onCall: (@Sendable (PrometheusEndpoint) -> Void)? = nil) {
        self.stubbedResult = result
        self.onCall = onCall
    }

    func instantQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        onCall?(endpoint)
        return stubbedResult
    }

    func rangeQuery(
        _ query: PromQuery,
        endpoint: PrometheusEndpoint
    ) async throws -> PromQueryResult {
        onCall?(endpoint)
        return stubbedResult
    }
}
