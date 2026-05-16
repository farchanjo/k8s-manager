// Views/Sidebar/SidebarTreeView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (sidebar taxonomy + tab system), ADR-0051 (Lens-style layout)

import SwiftUI
import SharedKernel

// MARK: - SidebarTreeView

/// Lens-style hierarchical resource tree rendered in the sidebar column.
///
/// Uses SwiftUI `OutlineGroup` for native disclosure triangles driven by
/// `SidebarNode.children`. Selection is bound to `SidebarTreeViewModel.selectedNode`
/// so the list highlight and tab opening stay in sync.
///
/// The view starts the view-model's cluster-strip subscription via `.task { await
/// viewModel.start() }` which is cancelled automatically when the view is removed.
///
/// Layout: `List(.sidebar)` at minimum 220 pt width per ADR-0021.
public struct SidebarTreeView: View {

    // MARK: State

    @State private var viewModel = SidebarTreeViewModel()

    // MARK: Init

    public init() {}

    // MARK: Body

    public var body: some View {
        List(selection: $viewModel.selectedNode) {
            clusterContent
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .task { await viewModel.start() }
    }

    // MARK: Private

    @ViewBuilder
    private var clusterContent: some View {
        if !viewModel.hasReceivedSnapshot {
            SidebarSkeleton()
                .listRowBackground(Color.clear)
        } else if let name = viewModel.activeClusterName {
            Section {
                treeOutline
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    if let provider = viewModel.activeProviderKind {
                        Text(provider.displayLabel)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.tertiary)
                            .textCase(.uppercase)
                    }
                    ClusterHeaderRow(name: name, isConnected: viewModel.isConnected)
                }
            }
        } else {
            emptyState
        }
    }

    private var treeOutline: some View {
        OutlineGroup(
            SidebarTree.standardCategories(),
            id: \.self,
            children: \.children
        ) { node in
            SidebarRowView(node: node)
                .tag(node)
        }
        .onChange(of: viewModel.selectedNode) { _, newNode in
            guard let node = newNode else { return }
            Task { await viewModel.activate(node) }
        }
    }

    private var emptyState: some View {
        Text("No cluster selected")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
    }
}
