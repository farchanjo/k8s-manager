// PrometheusDiscoveryServiceTests.swift — metrics_observability bounded context
// Coverage: PrometheusDiscoveryService — delegation to EndpointDiscoveryPort,
//           result sorting, empty-result passthrough.

import Dependencies
import Foundation
import XCTest

@testable import MetricsObservability

// MARK: - PrometheusDiscoveryServiceTests

final class PrometheusDiscoveryServiceTests: XCTestCase {

    // MARK: - Delegation

    func test_discover_delegates_to_endpointDiscoveryPort() async throws {
        let contextId = UUID()
        let fake = StubEndpointDiscoveryPort(
            contextId: contextId,
            endpoints: [
                makeEndpoint(
                    contextId: contextId,
                    url: "http://prometheus.monitoring.svc:9090",
                    source: .autoAnnotation
                ),
            ]
        )
        let service = withDependencies {
            $0.endpointDiscovery = fake
        } operation: {
            PrometheusDiscoveryService()
        }

        let results = try await service.discover(in: contextId)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].discoverySource, .autoAnnotation)
    }

    // MARK: - Empty result

    func test_discover_returnsEmptyArray_when_noServicesFound() async throws {
        let contextId = UUID()
        let fake = StubEndpointDiscoveryPort(contextId: contextId, endpoints: [])
        let service = withDependencies {
            $0.endpointDiscovery = fake
        } operation: {
            PrometheusDiscoveryService()
        }

        let results = try await service.discover(in: contextId)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Sorting

    func test_discover_sorts_by_discoverySource_then_url() async throws {
        let contextId = UUID()
        let endpoints = [
            makeEndpoint(contextId: contextId, url: "http://z-prom:9090", source: .autoLabel),
            makeEndpoint(contextId: contextId, url: "http://a-prom:9090", source: .autoAnnotation),
            makeEndpoint(contextId: contextId, url: "http://b-prom:9090", source: .autoLabel),
        ]
        let fake = StubEndpointDiscoveryPort(contextId: contextId, endpoints: endpoints)
        let service = withDependencies {
            $0.endpointDiscovery = fake
        } operation: {
            PrometheusDiscoveryService()
        }

        let results = try await service.discover(in: contextId)
        // autoAnnotation rawValue "auto_annotation" < autoLabel rawValue "auto_label"
        XCTAssertEqual(results[0].url, "http://a-prom:9090")
        XCTAssertEqual(results[0].discoverySource, .autoAnnotation)
        // within autoLabel, urls sorted ASC
        XCTAssertEqual(results[1].url, "http://b-prom:9090")
        XCTAssertEqual(results[2].url, "http://z-prom:9090")
    }
}

// MARK: - Helpers

private func makeEndpoint(
    contextId: UUID,
    url: String,
    source: DiscoverySource
) -> PrometheusEndpoint {
    PrometheusEndpoint(
        id: UUID(),
        kubernetesContextId: contextId,
        url: url,
        discoverySource: source,
        authStrategy: .none
    )
}

// MARK: - StubEndpointDiscoveryPort

private struct StubEndpointDiscoveryPort: EndpointDiscoveryPort {
    let contextId: UUID
    let endpoints: [PrometheusEndpoint]

    func discover(kubernetesContextId: UUID) async throws -> [PrometheusEndpoint] {
        endpoints
    }

    func probe(_ endpoint: PrometheusEndpoint) async throws -> PrometheusEndpoint {
        endpoint.probedWith(status: .healthy, probedAt: "2024-01-01T00:00:00Z")
    }
}
