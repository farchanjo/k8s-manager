// Views/ResourceBrowserView.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0013 (kind catalogue)

import SwiftUI
import ResourceBrowser

// MARK: - ResourceBrowserView

/// Root view for the resource browser vertical slice.
///
/// Presents a toolbar with a kind picker and namespace filter, then renders
/// the resource list in one of three states: loading, failure (with retry),
/// or success (table of `ResourceListItem` rows). Tapping a row opens a
/// detail panel that shows the resource name, namespace, status, and age.
///
/// Three-state rendering follows ADR-0031: idle and loading share a single
/// progress indicator; success shows the resource list; failure shows an
/// inline error with a retry affordance.
@MainActor
public struct ResourceBrowserView: View {

    @State private var viewModel = ResourceBrowserViewModel()

    /// Ordered list of kind names shown in the picker toolbar.
    private static let supportedKinds: [String] = [
        "Pod", "Deployment", "Service", "ConfigMap", "Secret", "Ingress",
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Resources")
                .toolbar { toolbarContent }
                .task { await viewModel.load(kind: viewModel.selectedKind, namespace: viewModel.namespace) }
        }
    }

    // MARK: Private views

    @ViewBuilder
    private var content: some View {
        switch viewModel.resources {
        case .idle, .loading:
            loadingView
        case .failure(let error):
            errorView(error)
        case .success(let items):
            resourceTable(items)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading \(viewModel.selectedKind)s…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
                .font(.body)
            Button("Retry") {
                Task { await viewModel.load(kind: viewModel.selectedKind, namespace: viewModel.namespace) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resourceTable(_ items: [ResourceListItem]) -> some View {
        HSplitView {
            itemList(items)
            detailPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func itemList(_ items: [ResourceListItem]) -> some View {
        List(items, id: \.id, selection: Binding(
            get: { viewModel.selectedItem },
            set: { viewModel.select($0) }
        )) { item in
            itemRow(item)
        }
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func itemRow(_ item: ResourceListItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline)
                if let ns = item.namespace {
                    Text(ns).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(item.status)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
            Text(ageLabel(seconds: item.ageSeconds))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let item = viewModel.selectedItem {
            resourceDetail(item)
        } else {
            ContentUnavailableView(
                "Select a resource",
                systemImage: "list.bullet.rectangle",
                description: Text("Pick a row to view its details")
            )
        }
    }

    private func resourceDetail(_ item: ResourceListItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.name).font(.title2).bold()
            Divider()
            detailRow(label: "Kind", value: item.gvk.kind)
            detailRow(label: "Namespace", value: item.namespace ?? "cluster-scoped")
            detailRow(label: "Status", value: item.status)
            detailRow(label: "Age", value: ageLabel(seconds: item.ageSeconds))
            detailRow(label: "UID", value: item.uid)
            Spacer()
        }
        .padding()
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":").font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
            Text(value).font(.caption).textSelection(.enabled)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            kindPicker
        }
        ToolbarItem(placement: .primaryAction) {
            namespacePicker
        }
        ToolbarItem(placement: .primaryAction) {
            refreshButton
        }
    }

    private var kindPicker: some View {
        Picker("Kind", selection: Binding(
            get: { viewModel.selectedKind },
            set: { newKind in
                Task { await viewModel.load(kind: newKind, namespace: viewModel.namespace) }
            }
        )) {
            ForEach(Self.supportedKinds, id: \.self) { kind in
                Text(kind).tag(kind)
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 120)
    }

    private var namespacePicker: some View {
        TextField("Namespace", text: Binding(
            get: { viewModel.namespace },
            set: { viewModel.namespace = $0 }
        ))
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 120, maxWidth: 180)
        .onSubmit {
            Task { await viewModel.load(kind: viewModel.selectedKind, namespace: viewModel.namespace) }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.load(kind: viewModel.selectedKind, namespace: viewModel.namespace) }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }
    }

    // MARK: Formatting helpers

    private func ageLabel(seconds: Int) -> String {
        switch seconds {
        case ..<60:         return "\(seconds)s"
        case ..<3600:       return "\(seconds / 60)m"
        case ..<86400:      return "\(seconds / 3600)h"
        default:            return "\(seconds / 86400)d"
        }
    }
}
