// Views/Chrome/GlobalNamespacePill.swift — app_shell bounded context
// DDD role: View — chrome-row pill driving the cluster-wide namespace filter
// ADR ref: ADR-0069 (global namespace pill in top-right chrome)

import Dependencies
import Logging
import ResourceBrowser
import SharedKernel
import SwiftUI

private let log = Logger(label: "k8smgr.app_shell.global_namespace_pill")

// MARK: - GlobalNamespacePill

/// Compact pill displayed in the top-right chrome row that controls the
/// cluster-wide namespace filter.
///
/// Writing to the shared ``NamespaceFilterActor`` causes every subscribed
/// workload and config list view model to re-fetch for the new namespace.
/// Namespaces are loaded once per cluster on `.task(id: clusterId)` and
/// refreshed on demand via the trailing arrow button. API failures fall back
/// to the hard-coded quick-pick set so the pill never becomes unusable.
@MainActor
public struct GlobalNamespacePill: View {

    public let clusterId: ClusterId

    @State private var selection: String?
    @State private var namespaces: [String] = []
    @State private var isLoading: Bool = false

    @Dependency(\.namespaceFilter) private var filter
    @Dependency(\.kubernetesResourceList) private var listPort

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        HStack(spacing: 4) {
            pillLabel
            menuChevron
            refreshButton
        }
        .padding(.horizontal, 8)
        .frame(minWidth: 180, maxWidth: 220, minHeight: 26, maxHeight: 26)
        .background(.regularMaterial, in: Capsule())
        .task(id: clusterId) { await bootstrap() }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("GlobalNamespacePill")
    }

    // MARK: Private subviews

    private var pillLabel: some View {
        Menu {
            namespaceMenuItems
        } label: {
            Text(selection ?? "All namespaces")
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuChevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private var refreshButton: some View {
        Button {
            Task { await loadNamespaces() }
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
            }
            .frame(width: 14, height: 14)
        }
        .buttonStyle(.borderless)
        .disabled(isLoading)
        .accessibilityLabel("Refresh namespaces")
    }

    @ViewBuilder
    private var namespaceMenuItems: some View {
        Button("All namespaces") {
            applySelection(nil)
        }
        Divider()
        ForEach(displayNamespaces, id: \.self) { ns in
            Button(ns) { applySelection(ns) }
        }
    }

    // MARK: Private helpers

    private var displayNamespaces: [String] {
        let list = namespaces.isEmpty ? Self.quickNamespaces : namespaces
        return Array(Set(list)).sorted()
    }

    private var accessibilityLabel: String {
        "Namespace filter: \(selection ?? "All namespaces")"
    }

    private static let quickNamespaces: [String] = [
        "default", "kube-system", "kube-public", "kube-node-lease",
    ]

    private func applySelection(_ namespace: String?) {
        selection = namespace
        Task { await filter.setNamespace(namespace, for: clusterId) }
    }

    /// Seeds current selection, loads namespaces, then subscribes to future
    /// actor mutations so external changes (command palette, drawer links) keep
    /// the pill label in sync for the lifetime of the view.
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
        isLoading = true
        defer { isLoading = false }
        let gvk = GroupVersionKind.core("Namespace")
        do {
            let items = try await listPort.list(gvk: gvk, namespace: nil, clusterId: clusterId)
            namespaces = items.map(\.name).sorted()
        } catch {
            log.warning("namespace list failed cluster=\(clusterId.rawValue) — \(error)")
        }
    }
}
