// Actors/PrometheusRowMetricFeedAdapter.swift — app_shell bounded context
// DDD role: Adapter — implements RowMetricFeedPort via PrometheusQueryPort
// ADR ref: ADR-0059 (Prometheus row metric mini-bars)

import Foundation
import Dependencies
import Logging
import MetricsObservability

// MARK: - PrometheusRowMetricFeedAdapter

/// Concrete adapter that feeds CPU and Memory metric series into list-view rows
/// by executing PromQL instant queries against the first configured Prometheus
/// endpoint for the active cluster.
///
/// PromQL expressions per ADR-0059:
/// - Pod CPU:    `rate(container_cpu_usage_seconds_total{pod="<name>",namespace="<ns>",container!="POD"}[5m])`
/// - Pod Memory: `container_memory_working_set_bytes{pod="<name>",namespace="<ns>",container!="POD"}`
/// - Node CPU:   `1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle",node="<name>"}[5m]))`
/// - Node Memory:`node_memory_MemTotal_bytes{node="<name>"} - node_memory_MemAvailable_bytes{node="<name>"}`
///
/// When no endpoint is configured or queries fail, falls back to
/// `.unavailable` series so `MetricMiniBar` renders a neutral greyed bar.
public struct PrometheusRowMetricFeedAdapter: RowMetricFeedPort, Sendable {

    @Dependency(\.prometheusQuery) private var queryPort
    @Dependency(\.prometheusEndpointRepository) private var endpointRepository

    private let logger = Logger(label: "k8smgr.app_shell.prometheus_row_feed")

    public init() {}

    // MARK: - RowMetricFeedPort

    /// Returns CPU + Memory metric series for a Kubernetes node.
    public func metrics(forNode nodeName: String) async -> [MetricSeries] {
        guard let endpoint = await firstEndpoint() else {
            return unavailableAll(dimensions: [.cpu, .memory])
        }
        async let cpuResult    = queryCPU(forNode: nodeName, endpoint: endpoint)
        async let memoryResult = queryMemory(forNode: nodeName, endpoint: endpoint)
        return await [cpuResult, memoryResult]
    }

    /// Returns CPU + Memory metric series for a Kubernetes pod.
    public func metrics(forPodNamespace ns: String, name: String) async -> [MetricSeries] {
        guard let endpoint = await firstEndpoint() else {
            return unavailableAll(dimensions: [.cpu, .memory])
        }
        async let cpuResult    = queryCPU(forPod: name, namespace: ns, endpoint: endpoint)
        async let memoryResult = queryMemory(forPod: name, namespace: ns, endpoint: endpoint)
        return await [cpuResult, memoryResult]
    }

    // MARK: - Private — PromQL execution

    private func queryCPU(forPod name: String, namespace: String, endpoint: PrometheusEndpoint) async -> MetricSeries {
        let expr = #"sum(rate(container_cpu_usage_seconds_total{pod="\#(name)",namespace="\#(namespace)",container!="POD"}[5m]))"#
        return await instantSeriesValue(expr: expr, endpoint: endpoint, dimension: .cpu) { value in
            // CPU is in cores — capacity here is an advisory 1 core for normalisation.
            MetricSeries.available(dimension: .cpu, value: value, capacity: 1.0)
        }
    }

    private func queryMemory(forPod name: String, namespace: String, endpoint: PrometheusEndpoint) async -> MetricSeries {
        let expr = #"sum(container_memory_working_set_bytes{pod="\#(name)",namespace="\#(namespace)",container!="POD"})"#
        return await instantSeriesValue(expr: expr, endpoint: endpoint, dimension: .memory) { value in
            MetricSeries.available(dimension: .memory, value: value, capacity: value * 2)
        }
    }

    private func queryCPU(forNode nodeName: String, endpoint: PrometheusEndpoint) async -> MetricSeries {
        let expr = #"1 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle",node="\#(nodeName)"}[5m]))"#
        return await instantSeriesValue(expr: expr, endpoint: endpoint, dimension: .cpu) { value in
            MetricSeries.available(dimension: .cpu, value: value, capacity: 1.0)
        }
    }

    private func queryMemory(forNode nodeName: String, endpoint: PrometheusEndpoint) async -> MetricSeries {
        let total = #"node_memory_MemTotal_bytes{node="\#(nodeName)"}"#
        let avail = #"node_memory_MemAvailable_bytes{node="\#(nodeName)"}"#
        let expr  = "\(total) - \(avail)"
        return await instantSeriesValue(expr: expr, endpoint: endpoint, dimension: .memory) { value in
            MetricSeries.available(dimension: .memory, value: value, capacity: value * 2)
        }
    }

    // MARK: - Private — helpers

    private func instantSeriesValue(
        expr: String,
        endpoint: PrometheusEndpoint,
        dimension: MetricDimension,
        transform: (Double) -> MetricSeries
    ) async -> MetricSeries {
        let query = PromQuery.instant(expr: expr)
        do {
            let result = try await queryPort.instantQuery(query, endpoint: endpoint)
            guard case .instantVector(let samples) = result,
                  let sample = samples.first else {
                return .unavailable(dimension: dimension)
            }
            return transform(sample.value)
        } catch {
            logger.debug("prometheus row feed query failed — \(error)")
            return .unavailable(dimension: dimension)
        }
    }

    private func firstEndpoint() async -> PrometheusEndpoint? {
        do {
            let endpoints = try await endpointRepository.load()
            return endpoints.first
        } catch {
            logger.debug("prometheus endpoint load failed — \(error)")
            return nil
        }
    }

    private func unavailableAll(dimensions: [MetricDimension]) -> [MetricSeries] {
        dimensions.map { MetricSeries.unavailable(dimension: $0) }
    }
}

// MARK: - DependencyKey

private enum RowMetricFeedPortKey: DependencyKey {
    static let liveValue: any RowMetricFeedPort = PrometheusRowMetricFeedAdapter()
    static let testValue: any RowMetricFeedPort = StubRowMetricFeedAdapter()
}

// MARK: - DependencyValues

public extension DependencyValues {
    /// Live: `PrometheusRowMetricFeedAdapter`.  Tests: `StubRowMetricFeedAdapter`.
    var rowMetricFeed: any RowMetricFeedPort {
        get { self[RowMetricFeedPortKey.self] }
        set { self[RowMetricFeedPortKey.self] = newValue }
    }
}
