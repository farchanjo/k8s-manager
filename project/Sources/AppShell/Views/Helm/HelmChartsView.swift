// Views/Helm/HelmChartsView.swift — app_shell bounded context
// DDD role: View — Helm charts browser (Onda 2 / Phase 1 stub)
// ADR ref: ADR-0015 §Phase 2 (OCI chart pull declared, not yet implemented)

import SwiftUI
import SharedKernel
import HelmManagement

// MARK: - HelmChartsView

/// Browse Helm charts from configured repositories.
///
/// Phase 1: The `ChartRepositoryPort` always throws `notImplementedPhase2`,
/// so this view shows an informational empty state with a stub repository list.
/// The toolbar, repo picker, search, and chart-card grid scaffold are fully wired
/// so Phase 2 can fill in live data without structural changes.
public struct HelmChartsView: View {

    public let clusterId: ClusterId

    @State private var searchText: String = ""
    @State private var selectedRepo: String? = nil
    @State private var selectedChart: ChartMetadata?
    @State private var showChartDetail: Bool = false

    /// Phase 1 stub repositories — replaced by ChartRepositoryPort in Phase 2.
    private static let stubRepos: [String] = [
        "stable", "bitnami", "ingress-nginx",
    ]

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        VStack(spacing: 0) {
            chartsToolbar
            Divider()
            phase1EmptyState
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showChartDetail) {
            if let chart = selectedChart {
                HelmChartDetailView(chart: chart, clusterId: clusterId)
            }
        }
    }

    // MARK: Toolbar

    private var chartsToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary).imageScale(.small)
            TextField("Search charts…", text: $searchText)
                .textFieldStyle(.plain)
            Spacer()
            repoPicker
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var repoPicker: some View {
        HStack(spacing: 4) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary).imageScale(.small)
            Picker("Repository", selection: $selectedRepo) {
                Text("All Repos").tag(String?.none)
                Divider()
                ForEach(Self.stubRepos, id: \.self) { repo in
                    Text(repo).tag(String?.some(repo))
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 140)
        }
    }

    // MARK: Phase 1 placeholder

    private var phase1EmptyState: some View {
        ContentUnavailableView {
            Label("Chart Browser — Phase 2", systemImage: "doc.richtext")
        } description: {
            Text(
                "OCI and HTTP chart repository browsing will be available in Phase 2. " +
                "Installed chart metadata is visible from the Releases tab."
            )
        } actions: {
            Button("View Releases") {}
                .buttonStyle(.borderedProminent)
        }
    }
}
