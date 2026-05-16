// Views/Security/SecurityImagesView.swift — app_shell bounded context
// DDD role: View — container image inventory with vuln scan status
// ADR ref: ADR-0021 (AppShell orchestration shell extended for Onda 2 security lens)

import SwiftUI
import SharedKernel

// MARK: - SecurityImagesViewModel

/// Lightweight view model scoped to the image list view.
///
/// In production, populates `images` by querying all pod specs for container
/// image references, then resolving Trivy VulnerabilityReport CRDs when present.
@Observable
@MainActor
final class SecurityImagesViewModel {

    /// Sorted list of deduplicated image summaries.
    var images: [ImageSummary] = []
    /// Lifecycle state.
    var loadState: AsyncResource<Void> = .idle
    /// Current sort order.
    var sortOrder: SortOrder = .vulnCount

    enum SortOrder: String, CaseIterable {
        case name       = "Name"
        case podCount   = "Pod Count"
        case vulnCount  = "Vuln Count"
    }

    var sortedImages: [ImageSummary] {
        switch sortOrder {
        case .name:      return images.sorted { $0.imageRef < $1.imageRef }
        case .podCount:  return images.sorted { $0.podCount > $1.podCount }
        case .vulnCount: return images.sorted { $0.vulnCount > $1.vulnCount }
        }
    }

    func load(clusterId: ClusterId) async {
        loadState = .loading
        // Production: query pod specs + Trivy CRDs via KubernetesSecurityListPort.
        // Placeholder returns an empty list so the view renders the configured empty state.
        images = []
        loadState = .success(())
    }
}

// MARK: - SecurityImagesView

/// Lists all container images across the cluster, deduplicated by image reference.
///
/// Per-image row shows pod count and Trivy scan status (when the CRD is present).
/// Table is sortable by name, pod count, or vulnerability count.
@MainActor
public struct SecurityImagesView: View {

    private let clusterId: ClusterId

    @State private var viewModel = SecurityImagesViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Container Images")
                .toolbar { sortPicker }
                .task { await viewModel.load(clusterId: clusterId) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            ProgressView("Loading image inventory…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            errorView(error)
        case .success where viewModel.images.isEmpty:
            emptyState
        case .success:
            imageTable
        }
    }

    private var imageTable: some View {
        Table(viewModel.sortedImages) {
            TableColumn("Image", value: \.imageRef)
            TableColumn("Pods") { row in
                Text("\(row.podCount)").monospacedDigit()
            }
            TableColumn("Scan Status") { row in
                ImageVulnStatusBadge(status: row.vulnStatus, vulnCount: row.vulnCount)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No images found",
            systemImage: "shippingbox",
            description: Text("No running pods with container images were detected in this cluster.")
        )
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
            Text(error.localizedDescription).font(.callout).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.load(clusterId: clusterId) } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var sortPicker: some ToolbarContent {
        ToolbarItem {
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(SecurityImagesViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }
}

// MARK: - ImageVulnStatusBadge

private struct ImageVulnStatusBadge: View {
    let status: ImageVulnStatus
    let vulnCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(badgeColor).frame(width: 8, height: 8)
            Text(label).font(.caption)
        }
    }

    private var label: String {
        switch status {
        case .clean:             return "Clean"
        case .vulnerable:        return "\(vulnCount) vuln(s)"
        case .scanNotConfigured: return "Scan not configured"
        case .pending:           return "Pending scan"
        }
    }

    private var badgeColor: Color {
        switch status {
        case .clean:             return .green
        case .vulnerable:        return .red
        case .scanNotConfigured: return .gray
        case .pending:           return .yellow
        }
    }
}
