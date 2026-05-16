// Views/GlobalNamespacePicker.swift — app_shell bounded context
// DDD role: View — toolbar picker driving the cluster-wide namespace filter
// ADR ref: ADR-0050 / ADR-0051 (single picker, every list view filters together)

import Dependencies
import Logging
import ResourceBrowser
import SharedKernel
import SwiftUI

private let log = Logger(label: "k8smgr.app_shell.global_namespace_picker")

// MARK: - GlobalNamespacePicker

/// Single namespace dropdown shown in the canvas header for the active cluster.
///
/// Reads/writes the shared ``NamespaceFilterActor`` so every workload list
/// view (Pods, Deployments, DaemonSets…) re-fetches whenever the operator
/// changes the selection here. Namespaces are loaded once per cluster from
/// the live `KubernetesResourceListPort`; failures fall back to the
/// hard-coded quick-pick set so the picker never disappears.
public struct GlobalNamespacePicker: View {

    public let clusterId: ClusterId

    @State private var selection: String?
    @State private var namespaces: [String] = []
    @State private var isLoadingNamespaces: Bool = false

    @Dependency(\.namespaceFilter) private var filter
    @Dependency(\.kubernetesResourceList) private var listPort

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        HStack(spacing: 6) {
            NamespaceFilterPicker(
                selection: Binding(
                    get: { selection },
                    set: { newValue in
                        selection = newValue
                        Task { await filter.setNamespace(newValue, for: clusterId) }
                    }
                ),
                namespaces: namespaces
            )
            if isLoadingNamespaces {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading namespaces")
            }
        }
        .task(id: clusterId) {
            await bootstrap()
        }
    }

    // MARK: Private

    /// Loads the cluster's namespaces and subscribes to filter changes so
    /// external mutations (e.g. command palette, future "filter by ns" links)
    /// keep this picker in sync.
    private func bootstrap() async {
        selection = await filter.current(for: clusterId)
        await loadNamespaces()
        for await snapshot in filter.stateStream(for: clusterId) {
            if selection != snapshot.namespace {
                selection = snapshot.namespace
            }
        }
    }

    private func loadNamespaces() async {
        isLoadingNamespaces = true
        defer { isLoadingNamespaces = false }
        let gvk = GroupVersionKind.core("Namespace")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: nil, clusterId: clusterId)
            namespaces = items.map(\.name).sorted()
        } catch {
            log.warning("namespaces load failed for cluster \(clusterId.rawValue) — \(error)")
        }
    }
}
