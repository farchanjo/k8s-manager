// Tests/AppShellTests/MenuBarTrayViewModelTests.swift
// Coverage: MenuBarTrayViewModel real-data-source wiring via fake dependencies.

import XCTest
import Dependencies
@testable import AppShell
import ClusterConnectivity
import MetricsObservability
import SharedKernel

// MARK: - MenuBarTrayViewModelTests

@MainActor
final class MenuBarTrayViewModelTests: XCTestCase {

    // MARK: Test 1 — cluster name populated from active kubeconfig context

    func test_refresh_populatesClusterNameFromActiveContext() async {
        let ctx = KubeconfigContext(name: "prod", cluster: "prod-cluster", user: "admin")
        let loader = FakeTrayKubeconfigLoader(contexts: [ctx], currentContext: "prod")
        let api = FakeTrayKubernetesApi(state: .reachable)
        let repo = FakeTrayEndpointRepo(endpoints: [])

        await withDependencies {
            $0.kubeconfigLoader = loader
            $0.kubernetesApi = api
            $0.prometheusEndpointRepository = repo
        } operation: {
            let sut = MenuBarTrayViewModel()
            await sut.refresh()
            XCTAssertEqual(sut.cluster.contextName, "prod")
            XCTAssertEqual(sut.cluster.health, .healthy)
        }
    }

    // MARK: Test 2 — unreachable cluster maps to .unreachable health

    func test_refresh_kubeApiError_setsUnreachableHealth() async {
        let ctx = KubeconfigContext(name: "dev", cluster: "dev-cluster", user: "admin")
        let loader = FakeTrayKubeconfigLoader(contexts: [ctx], currentContext: "dev")
        let api = FakeTrayKubernetesApi(error: KubernetesApiError.transportError(detail: "timeout"))
        let repo = FakeTrayEndpointRepo(endpoints: [])

        await withDependencies {
            $0.kubeconfigLoader = loader
            $0.kubernetesApi = api
            $0.prometheusEndpointRepository = repo
        } operation: {
            let sut = MenuBarTrayViewModel()
            await sut.refresh()
            XCTAssertEqual(sut.cluster.health, .unreachable)
        }
    }

    // MARK: Test 3 — metric tiles show dashes when no endpoint configured

    func test_refresh_noEndpoints_producesDashTiles() async {
        let loader = FakeTrayKubeconfigLoader(contexts: [], currentContext: nil)
        let api = FakeTrayKubernetesApi(state: .unknown)
        let repo = FakeTrayEndpointRepo(endpoints: [])

        await withDependencies {
            $0.kubeconfigLoader = loader
            $0.kubernetesApi = api
            $0.prometheusEndpointRepository = repo
        } operation: {
            let sut = MenuBarTrayViewModel()
            await sut.refresh()
            XCTAssertEqual(sut.metricTiles.count, 3)
            XCTAssertTrue(sut.metricTiles.allSatisfy { $0.value == "—" },
                          "All tiles should show '—' when no endpoint is available")
        }
    }

    // MARK: Test 4 — metric tiles populated from Prometheus result

    func test_refresh_prometheusEndpoint_populatesTiles() async {
        let ctx = KubeconfigContext(name: "prod", cluster: "c", user: "u")
        let loader = FakeTrayKubeconfigLoader(contexts: [ctx], currentContext: "prod")
        let api = FakeTrayKubernetesApi(state: .reachable)
        let endpoint = PrometheusEndpoint(
            id: UUID(),
            kubernetesContextId: UUID(),
            url: "http://prometheus:9090",
            discoverySource: .manualOverride,
            authStrategy: .none,
            status: .healthy
        )
        let repo = FakeTrayEndpointRepo(endpoints: [endpoint])
        let promQuery = FakeTrayPrometheusQuery(cpuValue: 42.5, memValue: 55.0, podsValue: 10)

        await withDependencies {
            $0.kubeconfigLoader = loader
            $0.kubernetesApi = api
            $0.prometheusEndpointRepository = repo
            $0.prometheusQuery = promQuery
        } operation: {
            let sut = MenuBarTrayViewModel()
            await sut.refresh()
            XCTAssertEqual(sut.metricTiles.count, 3)
            let cpuTile = sut.metricTiles.first { $0.id == "cpu" }
            XCTAssertNotNil(cpuTile)
            XCTAssertNotEqual(cpuTile?.value, "—", "CPU tile should show a numeric value")
        }
    }
}

// MARK: - Test doubles

private struct FakeTrayKubeconfigLoader: KubeconfigLoaderPort {
    let stubbedContexts: [KubeconfigContext]
    let stubbedCurrentContext: String?

    init(contexts: [KubeconfigContext], currentContext: String?) {
        self.stubbedContexts = contexts
        self.stubbedCurrentContext = currentContext
    }

    func load(from path: KubeconfigPath) async throws -> Kubeconfig {
        Kubeconfig(
            sourcePath: path,
            sourceMTimeRFC3339: "2026-01-01T00:00:00Z",
            currentContext: stubbedCurrentContext,
            contexts: stubbedContexts
        )
    }

    func parse(yaml: String) async throws -> Kubeconfig {
        Kubeconfig(
            sourcePath: KubeconfigPath("<clipboard>"),
            sourceMTimeRFC3339: "",
            currentContext: stubbedCurrentContext,
            contexts: stubbedContexts
        )
    }

    func contexts(in config: Kubeconfig) -> [KubeconfigContext] { config.contexts }

    func activeContext(in config: Kubeconfig) -> KubeconfigContext? {
        guard let current = config.currentContext else { return nil }
        return config.contexts.first { $0.name == current }
    }
}

private struct FakeTrayKubernetesApi: KubernetesApiPort {
    let stubbedState: HealthState?
    let stubbedError: Error?

    init(state: HealthState) {
        self.stubbedState = state
        self.stubbedError = nil
    }

    init(error: Error) {
        self.stubbedState = nil
        self.stubbedError = error
    }

    func probeHealth(clusterId: ClusterId) async throws -> HealthStatus {
        if let error = stubbedError { throw error }
        return HealthStatus(
            clusterId: clusterId,
            probedAt: "2026-01-01T00:00:00Z",
            state: stubbedState ?? .unknown
        )
    }

    func serverVersion(clusterId: ClusterId) async throws -> String {
        throw KubernetesApiError.unimplemented
    }
}

private struct FakeTrayEndpointRepo: PrometheusEndpointRepositoryPort {
    let stubbedEndpoints: [PrometheusEndpoint]

    init(endpoints: [PrometheusEndpoint]) {
        self.stubbedEndpoints = endpoints
    }

    func save(_ endpoints: [PrometheusEndpoint]) async throws {}

    func load() async throws -> [PrometheusEndpoint] { stubbedEndpoints }
}

private struct FakeTrayPrometheusQuery: PrometheusQueryPort {
    let cpuValue: Double
    let memValue: Double
    let podsValue: Double

    init(cpuValue: Double, memValue: Double, podsValue: Double) {
        self.cpuValue = cpuValue
        self.memValue = memValue
        self.podsValue = podsValue
    }

    func instantQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        let expr = query.expr
        if expr.contains("cpu") {
            return .instantVector([MetricSample(metric: [:], timestampUnix: 0, value: cpuValue)])
        } else if expr.contains("memory") || expr.contains("mem") {
            return .instantVector([MetricSample(metric: [:], timestampUnix: 0, value: memValue)])
        } else {
            return .scalar(timestampUnix: 0, value: podsValue)
        }
    }

    func rangeQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        throw PrometheusQueryError.unimplemented
    }
}
