// AuthStrategyTests.swift — PrometheusQueryAdapter test target
// Coverage: auth header injection in PrometheusHTTPClient.buildRequest
//           for .none, .bearer(token:), and .basic(username:password:).

import AsyncHTTPClient
import Foundation
import MetricsObservability
import XCTest

@testable import PrometheusQueryAdapter

// MARK: - AuthStrategyTests

final class AuthStrategyTests: XCTestCase {

    // MARK: - .none

    func test_authStrategy_none_adds_no_authorization_header() {
        let endpoint = makeEndpoint(auth: .none)
        let request = PrometheusHTTPClient(httpClient: HTTPClient.shared)
            .buildRequestForTest(url: "http://prometheus.test:9090/api/v1/query", endpoint: endpoint)
        XCTAssertNil(request.headers.first(name: "Authorization"))
    }

    // MARK: - .bearer(token:)

    func test_authStrategy_bearer_adds_bearer_authorization_header() {
        let token = "my-secret-token"
        let endpoint = makeEndpoint(auth: .bearer(token: token))
        let request = PrometheusHTTPClient(httpClient: HTTPClient.shared)
            .buildRequestForTest(url: "http://prometheus.test:9090/api/v1/query", endpoint: endpoint)
        let headerValue = request.headers.first(name: "Authorization")
        XCTAssertEqual(headerValue, "Bearer \(token)")
    }

    // MARK: - .basic(username:password:)

    func test_authStrategy_basic_adds_base64_authorization_header() {
        let endpoint = makeEndpoint(auth: .basic(username: "admin", password: "secret"))
        let request = PrometheusHTTPClient(httpClient: HTTPClient.shared)
            .buildRequestForTest(url: "http://prometheus.test:9090/api/v1/query", endpoint: endpoint)
        let headerValue = request.headers.first(name: "Authorization")
        let expectedCredentials = Data("admin:secret".utf8).base64EncodedString()
        XCTAssertEqual(headerValue, "Basic \(expectedCredentials)")
    }
}

// MARK: - Helpers

private func makeEndpoint(auth: AuthStrategy) -> PrometheusEndpoint {
    PrometheusEndpoint(
        id: UUID(),
        kubernetesContextId: UUID(),
        url: "http://prometheus.test:9090",
        discoverySource: .wellKnown,
        authStrategy: auth
    )
}

// MARK: - PrometheusHTTPClient test bridge

extension PrometheusHTTPClient {
    /// Convenience alias for use in tests.
    ///
    /// `buildRequest` has `internal` visibility; the alias documents intent and
    /// keeps test call sites stable if the production name changes.
    func buildRequestForTest(url: String, endpoint: PrometheusEndpoint) -> HTTPClientRequest {
        buildRequest(url: url, endpoint: endpoint)
    }
}
