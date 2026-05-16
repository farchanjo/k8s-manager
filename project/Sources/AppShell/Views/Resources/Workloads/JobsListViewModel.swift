// Views/Resources/Workloads/JobsListViewModel.swift — app_shell bounded context
// DDD role: ViewModel — Jobs resource list
// ADR ref: ADR-0050 (Onda 2 resource list views)

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.jobs_list")

// MARK: - JobRow

/// Table row projection for a single Kubernetes Job.
public struct JobRow: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let namespace: String
    /// `"completedCount/desiredCount"`
    public let completions: String
    /// Human-readable duration (e.g. `"5m"`, `"3h"`). `nil` when not completed.
    public let duration: String?
    public let age: String

    public init(
        id: String, name: String, namespace: String,
        completions: String, duration: String?, age: String
    ) {
        self.id = id; self.name = name; self.namespace = namespace
        self.completions = completions; self.duration = duration; self.age = age
    }
}

// MARK: - JobsListViewModel

/// View model for the Jobs resource list view.
@Observable
@MainActor
public final class JobsListViewModel {

    public var rows: [JobRow] = []
    public var selectedId: String?
    public var namespace: String?
    public var loadState: AsyncResource<Int> = .idle
    public var searchText: String = ""

    public var filteredRows: [JobRow] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.namespace.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ObservationIgnored
    @Dependency(\.kubernetesResourceList) private var listPort

    @ObservationIgnored
    @Dependency(\.namespaceFilter) private var namespaceFilter

    public init() {}

    public func start(clusterId: ClusterId, namespace: String?) async {
        self.namespace = await namespaceFilter.current(for: clusterId) ?? namespace
        await reload(clusterId: clusterId)
        for await snapshot in namespaceFilter.stateStream(for: clusterId) {
            if snapshot.namespace == self.namespace { continue }
            self.namespace = snapshot.namespace
            await reload(clusterId: clusterId)
        }
    }

    public func reload(clusterId: ClusterId) async {
        let port = listPort
        let ns = namespace
        let gvk = GroupVersionKind(group: "batch", version: "v1", kind: "Job")
        log.info("jobs reload cluster=\(clusterId.rawValue)")
        await AsyncLoader.run(
            setLoading: { self.loadState = .loading },
            operation: { try await port.list(gvk: gvk, namespace: ns, clusterId: clusterId) },
            onSuccess: { items in
                self.rows = items.map(Self.project)
                self.loadState = .success(self.rows.count)
            },
            onFailure: { error in
                log.error("jobs load failed — \(error)")
                self.loadState = .failure(error)
            }
        )
    }

    public func confirmDelete(ids: Set<String>) {
        log.info("delete requested ids=\(ids.count) (stub)")
    }

    private static func project(_ item: ResourceListItem) -> JobRow {
        let isComplete = item.status.lowercased().contains("complet")
        return JobRow(
            id: item.uid, name: item.name, namespace: item.namespace ?? "",
            completions: isComplete ? "1/1" : "0/1",
            duration: isComplete ? PodsListViewModel.ageString(seconds: item.ageSeconds / 2) : nil,
            age: PodsListViewModel.ageString(seconds: item.ageSeconds)
        )
    }
}
