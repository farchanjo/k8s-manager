// Tests/AppShellTests/Detail/ResourceDetailViewModelTests.swift
// Coverage: ResourceDetailViewModel — start, Prometheus fallback, action routing.

import XCTest
import Dependencies
@testable import AppShell
import ResourceBrowser
import MetricsObservability
import SharedKernel

// MARK: - ResourceDetailViewModelTests

@MainActor
final class ResourceDetailViewModelTests: XCTestCase {

    // MARK: Test doubles

    private let podRef = ResourceRef(
        kind: ResourceKind(group: "", version: "v1", kind: "Pod"),
        namespace: "default",
        name: "nginx-abc12"
    )

    private let clusterId = ClusterId("test-cluster")

    // MARK: start — properties populated

    func test_start_populatesProperties_onSuccess() async {
        let detail = makeDetail(name: "nginx-abc12", namespace: "default", status: "Running")
        let fakeList = FakeResourceListPort(detail: detail)

        await withDependencies {
            $0.kubernetesResourceList = fakeList
            $0.prometheusQuery = AlwaysFailingPrometheusPort()
        } operation: {
            let sut = ResourceDetailViewModel()
            await sut.start(clusterId: clusterId, ref: podRef)
            XCTAssertFalse(sut.properties.isEmpty, "Properties should be populated after successful fetch")
            let names = sut.properties.map(\.label)
            XCTAssertTrue(names.contains("Name"), "Name property expected")
            XCTAssertTrue(names.contains("Status"), "Status property expected")
        }
    }

    // MARK: start — Prometheus unavailable

    func test_start_prometheusUnavailable_whenPortThrows() async {
        let detail = makeDetail(name: "nginx-abc12", namespace: "default", status: "Running")
        let fakeList = FakeResourceListPort(detail: detail)

        await withDependencies {
            $0.kubernetesResourceList = fakeList
            $0.prometheusQuery = AlwaysFailingPrometheusPort()
        } operation: {
            let sut = ResourceDetailViewModel()
            await sut.start(clusterId: clusterId, ref: podRef)
            XCTAssertTrue(sut.prometheusUnavailable, "prometheusUnavailable should be true when port throws")
            XCTAssertTrue(sut.metricSeries.isEmpty, "metricSeries should be empty when Prometheus unavailable")
        }
    }

    // MARK: start — list port failure leaves properties empty

    func test_start_listFailure_leavesPropertiesEmpty() async {
        let fakeList = FakeResourceListPort(error: ResourceListError.notFound(
            name: "missing", gvk: .core("Pod")
        ))

        await withDependencies {
            $0.kubernetesResourceList = fakeList
            $0.prometheusQuery = AlwaysFailingPrometheusPort()
        } operation: {
            let sut = ResourceDetailViewModel()
            await sut.start(clusterId: clusterId, ref: podRef)
            XCTAssertTrue(sut.properties.isEmpty, "properties should be empty on list port failure")
        }
    }

    // MARK: openEditor posts yamlEditor tab

    func test_openEditor_postsYamlEditorTab() {
        let sut = ResourceDetailViewModel()
        var capturedTab: DocumentTab?
        sut.onOpenTab = { capturedTab = $0 }
        sut.openEditor(clusterId: clusterId, ref: podRef)

        guard case .yamlEditor(let cid, let ref, _) = capturedTab else {
            XCTFail("Expected .yamlEditor tab")
            return
        }
        XCTAssertEqual(cid, clusterId)
        XCTAssertEqual(ref.name, podRef.name)
    }

    // MARK: openShell posts exec tab

    func test_openShell_postsExecTab() {
        let sut = ResourceDetailViewModel()
        var capturedTab: DocumentTab?
        sut.onOpenTab = { capturedTab = $0 }
        sut.openShell(clusterId: clusterId, ref: podRef, container: "nginx")

        guard case .exec(let cid, let ref, let container) = capturedTab else {
            XCTFail("Expected .exec tab")
            return
        }
        XCTAssertEqual(cid, clusterId)
        XCTAssertEqual(ref.name, podRef.name)
        XCTAssertEqual(container, "nginx")
    }

    // MARK: openLogs posts logs tab

    func test_openLogs_postsLogsTab() {
        let sut = ResourceDetailViewModel()
        var capturedTab: DocumentTab?
        sut.onOpenTab = { capturedTab = $0 }
        sut.openLogs(clusterId: clusterId, ref: podRef, container: "sidecar")

        guard case .logs(let cid, let ref, let container, let follow) = capturedTab else {
            XCTFail("Expected .logs tab")
            return
        }
        XCTAssertEqual(cid, clusterId)
        XCTAssertEqual(ref.name, podRef.name)
        XCTAssertEqual(container, "sidecar")
        XCTAssertTrue(follow, "follow should be true by default")
    }

    // MARK: close invokes onClose

    func test_close_invokesOnClose() {
        let sut = ResourceDetailViewModel()
        var closeCalled = false
        sut.onClose = { closeCalled = true }
        sut.close()
        XCTAssertTrue(closeCalled)
    }

    // MARK: Prometheus success — metricSeries populated

    func test_start_prometheusSuccess_populatesMetricSeries() async {
        let detail = makeDetail(name: "nginx-abc12", namespace: "default", status: "Running")
        let fakeList = FakeResourceListPort(detail: detail)
        let points = [DataPoint(tUnix: 1_700_000_000, value: 0.05)]
        let series = [TimeSeries(metric: [:], points: points)]
        let fakeMetrics = FakePrometheusPort(stubbedResult: .rangeMatrix(series))

        await withDependencies {
            $0.kubernetesResourceList = fakeList
            $0.prometheusQuery = fakeMetrics
        } operation: {
            let sut = ResourceDetailViewModel()
            await sut.start(clusterId: clusterId, ref: podRef)
            XCTAssertFalse(sut.prometheusUnavailable)
            XCTAssertEqual(sut.metricSeries.count, 1)
        }
    }

    // MARK: Helpers

    private func makeDetail(name: String, namespace: String, status: String) -> ResourceDetail {
        let gvk = GroupVersionKind(group: "", version: "v1", kind: "Pod")
        let item = ResourceListItem(
            id: UUID(),
            gvk: gvk,
            namespace: namespace,
            name: name,
            uid: UUID().uuidString,
            creationTimestamp: "2026-01-01T00:00:00Z",
            status: status,
            ageSeconds: 3600
        )
        return ResourceDetail(listItem: item, rawJSON: "{}")
    }
}

// MARK: - Test doubles

private struct FakeResourceListPort: KubernetesResourceListPort {
    let stubbedDetail: ResourceDetail?
    let stubbedError: Error?

    init(detail: ResourceDetail) {
        self.stubbedDetail = detail
        self.stubbedError = nil
    }

    init(error: Error) {
        self.stubbedDetail = nil
        self.stubbedError = error
    }

    func list(gvk: GroupVersionKind, namespace: String?, clusterId: ClusterId) async throws -> [ResourceListItem] {
        if let error = stubbedError { throw error }
        return stubbedDetail.map { [$0.listItem] } ?? []
    }

    func get(gvk: GroupVersionKind, name: String, namespace: String?, clusterId: ClusterId) async throws -> ResourceDetail {
        if let error = stubbedError { throw error }
        return stubbedDetail!
    }
}

private struct AlwaysFailingPrometheusPort: PrometheusQueryPort {
    func instantQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        throw PrometheusQueryError.unimplemented
    }

    func rangeQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        throw PrometheusQueryError.unimplemented
    }
}

private struct FakePrometheusPort: PrometheusQueryPort {
    let stubbedResult: PromQueryResult

    func instantQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        stubbedResult
    }

    func rangeQuery(_ query: PromQuery, endpoint: PrometheusEndpoint) async throws -> PromQueryResult {
        stubbedResult
    }
}
