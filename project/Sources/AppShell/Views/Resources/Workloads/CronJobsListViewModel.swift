// Views/Resources/Workloads/CronJobsListViewModel.swift — app_shell bounded context
// DDD role: ViewModel — CronJobs resource list
// ADR ref: ADR-0050 (Onda 2 resource list views)

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.cronjobs_list")

// MARK: - CronJobRow

/// Table row projection for a single Kubernetes CronJob.
public struct CronJobRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let namespace: String
    public let schedule: String
    public let isSuspended: Bool
    public let activeCount: Int
    /// RFC3339 string of the last scheduled time, or `nil` when never run.
    public let lastSchedule: String?
    public let age: String

    public init(
        id: String, name: String, namespace: String,
        schedule: String, isSuspended: Bool, activeCount: Int,
        lastSchedule: String?, age: String
    ) {
        self.id = id; self.name = name; self.namespace = namespace
        self.schedule = schedule; self.isSuspended = isSuspended
        self.activeCount = activeCount; self.lastSchedule = lastSchedule; self.age = age
    }
}

// MARK: - CronJobsListViewModel

/// View model for the CronJobs resource list view.
@Observable
@MainActor
public final class CronJobsListViewModel {

    public var rows: [CronJobRow] = []
    public var selectedId: String?
    public var namespace: String?
    public var loadState: AsyncResource<Int> = .idle
    public var searchText: String = ""

    public var filteredRows: [CronJobRow] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.namespace.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    public init() {}

    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = namespace
        await reload(clusterId: clusterId)
    }

    public func reload(clusterId: ClusterId) async {
        loadState = .loading
        let gvk = GroupVersionKind(group: "batch", version: "v1", kind: "CronJob")
        log.info("cronjobs reload cluster=\(clusterId.rawValue)")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: namespace, clusterId: clusterId)
            rows = items.map(Self.project)
            loadState = .success(rows.count)
        } catch {
            log.error("cronjobs load failed — \(error)")
            loadState = .failure(error)
        }
    }

    public func confirmDelete(ids: Set<String>) {
        log.info("delete requested ids=\(ids.count) (stub)")
    }

    private static func project(_ item: ResourceListItem) -> CronJobRow {
        CronJobRow(
            id: item.uid, name: item.name, namespace: item.namespace ?? "",
            schedule: item.annotations["spec.schedule"] ?? "—",
            isSuspended: item.annotations["spec.suspend"] == "true",
            activeCount: 0,
            lastSchedule: nil,
            age: PodsListViewModel.ageString(seconds: item.ageSeconds)
        )
    }
}
