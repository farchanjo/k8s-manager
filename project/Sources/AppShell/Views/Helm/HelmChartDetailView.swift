// Views/Helm/HelmChartDetailView.swift — app_shell bounded context
// DDD role: View — Helm chart preview modal (Phase 1 read-only)
// ADR ref: ADR-0015 §Phase 2 (install wizard deferred)

import SwiftUI
import SharedKernel
import HelmManagement

// MARK: - HelmChartDetailView

/// Modal preview of a `ChartMetadata` value.
///
/// Displays:
///   - Chart name, version, app version, description, type, and maintainers.
///   - Dependencies list.
///   - Home and source URLs (clickable).
///   - An "Install" button stub (Phase 2 install wizard).
///
/// `ChartMetadata` is decoded from Helm release Secrets in Phase 1, so this view
/// is usable for installed chart info even before the OCI/HTTP fetch lands.
public struct HelmChartDetailView: View {

    public let chart: ChartMetadata
    public let clusterId: ClusterId

    @Environment(\.dismiss) private var dismiss

    public init(chart: ChartMetadata, clusterId: ClusterId) {
        self.chart = chart
        self.clusterId = clusterId
    }

    public var body: some View {
        NavigationStack {
            Form {
                overviewSection
                if !chart.dependencies.isEmpty { dependenciesSection }
                if !chart.maintainers.isEmpty { maintainersSection }
                if chart.home != nil || !chart.sources.isEmpty { linksSection }
            }
            .formStyle(.grouped)
            .navigationTitle(chart.name)
            .toolbar { toolbarItems }
        }
        .frame(minWidth: 520, minHeight: 440)
    }

    // MARK: Sections

    private var overviewSection: some View {
        Section("Overview") {
            LabeledContent("Version", value: chart.version)
            LabeledContent("App Version", value: chart.appVersion ?? "—")
            LabeledContent("API Version", value: chart.apiVersion.rawValue)
            if let type = chart.type {
                LabeledContent("Type", value: type.rawValue)
            }
            if let desc = chart.description {
                LabeledContent("Description") {
                    Text(desc)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var dependenciesSection: some View {
        Section("Dependencies (\(chart.dependencies.count))") {
            ForEach(chart.dependencies, id: \.name) { dep in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dep.name).fontWeight(.medium)
                        if let repo = dep.repository {
                            Text(repo).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(dep.version)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var maintainersSection: some View {
        Section("Maintainers") {
            ForEach(chart.maintainers, id: \.name) { m in
                HStack {
                    Text(m.name)
                    Spacer()
                    if let email = m.email {
                        Text(email)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var linksSection: some View {
        Section("Links") {
            if let home = chart.home, let url = URL(string: home) {
                Link(destination: url) {
                    Label("Home page", systemImage: "house")
                }
            }
            ForEach(Array(chart.sources.enumerated()), id: \.offset) { _, src in
                if let url = URL(string: src) {
                    Link(destination: url) {
                        Label(src, systemImage: "curlybraces")
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Install…") {}
                .buttonStyle(.borderedProminent)
                .help("Install wizard — Phase 2")
                .disabled(true)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { dismiss() }
        }
    }
}
