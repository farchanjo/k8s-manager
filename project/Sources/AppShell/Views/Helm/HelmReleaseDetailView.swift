// Views/Helm/HelmReleaseDetailView.swift — app_shell bounded context
// DDD role: View — Helm release detail (history + values + manifest + hooks)
// ADR ref: ADR-0015 (Helm native phased)

import SwiftUI
import SharedKernel
import HelmManagement
import Dependencies

// MARK: - ReleaseHistoryEntry + Identifiable

extension ReleaseHistoryEntry: Identifiable {
    /// Revision number uniquely identifies each history row.
    public var id: Int { revision }
}

// MARK: - HelmReleaseDetailView

/// Detail view for a single Helm release.
///
/// Sections:
///   - Header: name, chart, version, status badge, rollback + uninstall buttons.
///   - Revision history: table of `ReleaseHistoryEntry` values.
///   - Current values: YAML viewer (read-only).
///   - Manifest: rendered YAML viewer (read-only).
///   - Hooks: list of pre/post hooks declared by the chart.
public struct HelmReleaseDetailView: View {

    public let clusterId: ClusterId
    public let releaseName: String
    public let namespace: String

    @State private var release: AsyncResource<Release> = .idle
    @State private var history: AsyncResource<[ReleaseHistoryEntry]> = .idle
    @State private var selectedSection: DetailSection = .history
    @State private var showRollbackSheet: Bool = false

    @ObservationIgnored
    private let viewModel = HelmReleasesViewModel()

    public init(clusterId: ClusterId, releaseName: String, namespace: String) {
        self.clusterId = clusterId
        self.releaseName = releaseName
        self.namespace = namespace
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            headerBanner
            Divider()
            sectionPicker
            Divider()
            sectionContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await loadRelease() }
        .sheet(isPresented: $showRollbackSheet) {
            if let r = release.value {
                HelmRollbackSheet(
                    release: ReleaseRef(name: r.name, namespace: r.namespace),
                    currentRevision: r.version,
                    historyEntries: history.value ?? [],
                    clusterId: clusterId
                ) {
                    showRollbackSheet = false
                    Task { await loadRelease() }
                }
            }
        }
    }

    // MARK: Header

    private var headerBanner: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "shippingbox.fill")
                .font(.largeTitle)
                .foregroundStyle(.blue)
            headerInfo
            Spacer()
            actionButtons
        }
        .padding(16)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var headerInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(releaseName)
                .font(.title2).fontWeight(.semibold)
            if let r = release.value {
                Text("\(r.chart.name) \(r.chart.version)")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    HelmStatusBadge(status: r.status)
                    Text("Rev \(r.version)")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("ns: \(namespace)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(namespace)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button("Rollback…") { showRollbackSheet = true }
                .buttonStyle(.bordered)
                .disabled(release.value == nil)
            Button("Uninstall", role: .destructive) {
                Task { await uninstallCurrent() }
            }
            .buttonStyle(.bordered)
            .disabled(release.value == nil)
        }
    }

    // MARK: Section picker

    private var sectionPicker: some View {
        Picker("Section", selection: $selectedSection) {
            ForEach(DetailSection.allCases) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: Section content

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .history:  historySection
        case .values:   valuesSection
        case .manifest: manifestSection
        case .hooks:    hooksSection
        }
    }

    // MARK: History section

    @ViewBuilder
    private var historySection: some View {
        switch history {
        case .idle, .loading:
            ProgressView("Loading history…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            errorView(error, retry: loadRelease)
        case .success(let entries):
            historyTable(entries)
        }
    }

    private func historyTable(_ entries: [ReleaseHistoryEntry]) -> some View {
        Table(entries, selection: .constant(Set<Int>())) {
            TableColumn("Rev") { e in
                Text("\(e.revision)").monospacedDigit().fontWeight(.medium)
            }
            .width(40)
            TableColumn("Chart Version", value: \.chartVersion)
            TableColumn("App Version") { e in
                Text(e.appVersion ?? "—")
            }
            TableColumn("Status") { e in
                HelmStatusBadge(status: e.status)
            }
            TableColumn("Updated") { e in
                Text(e.deployedAtRFC3339)
                    .font(.caption).foregroundStyle(.secondary)
            }
            TableColumn("Description") { e in
                Text(e.description)
                    .lineLimit(1).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Values section

    @ViewBuilder
    private var valuesSection: some View {
        if let r = release.value {
            ScrollView {
                Text(r.valuesJSON)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else {
            loadingOrEmpty("values")
        }
    }

    // MARK: Manifest section

    @ViewBuilder
    private var manifestSection: some View {
        if let r = release.value {
            ScrollView {
                Text(r.manifestYAML)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else {
            loadingOrEmpty("manifest")
        }
    }

    // MARK: Hooks section

    @ViewBuilder
    private var hooksSection: some View {
        if let r = release.value {
            if r.hooks.isEmpty {
                ContentUnavailableView(
                    "No hooks",
                    systemImage: "hook",
                    description: Text("This chart declares no lifecycle hooks.")
                )
            } else {
                hooksList(r.hooks)
            }
        } else {
            loadingOrEmpty("hooks")
        }
    }

    private func hooksList(_ hooks: [HookManifest]) -> some View {
        List(hooks, id: \.name) { hook in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(hook.name).fontWeight(.medium)
                    Spacer()
                    Text(hook.kind)
                        .font(.caption)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.1), in: Capsule())
                        .foregroundStyle(.blue)
                }
                Text(hook.events.map(\.rawValue).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                Text("Weight: \(hook.weight) · \(hook.deletePolicy.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Helpers

    private func loadingOrEmpty(_ label: String) -> some View {
        ProgressView("Loading \(label)…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error, retry: @escaping () async -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle).foregroundStyle(.orange)
            Text(error.localizedDescription).multilineTextAlignment(.center)
            Button("Retry") { Task { await retry() } }
                .buttonStyle(.borderedProminent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Data loading

    private func loadRelease() async {
        release = .loading
        history = .loading
        do {
            let all = try await loadAllRevisions()
            guard let head = all.max(by: { $0.version < $1.version }) else {
                release = .failure(HelmDetailError.notFound(releaseName))
                history = .success([])
                return
            }
            release = .success(head)
            history = .success(projectHistory(from: all))
        } catch {
            release = .failure(error)
            history = .failure(error)
        }
    }

    @ObservationIgnored
    @Dependency(\.helmReleaseStore) private var releaseStore

    private func loadAllRevisions() async throws -> [Release] {
        let all = try await releaseStore.listReleases(clusterId: clusterId, namespace: namespace)
        return all.filter { $0.name == releaseName }
    }

    private func projectHistory(from releases: [Release]) -> [ReleaseHistoryEntry] {
        releases
            .sorted { $0.version > $1.version }
            .map { r in
                ReleaseHistoryEntry(
                    revision: r.version,
                    deployedAtRFC3339: r.modifiedAtRFC3339,
                    status: r.status,
                    chartVersion: r.chart.version,
                    appVersion: r.chart.appVersion,
                    description: r.info.description,
                    supersededAtRFC3339: nil
                )
            }
    }

    private func uninstallCurrent() async {
        guard let r = release.value else { return }
        await viewModel.uninstall(
            release: ReleaseRef(name: r.name, namespace: r.namespace),
            clusterId: clusterId
        )
    }
}

// MARK: - DetailSection

private enum DetailSection: String, CaseIterable, Identifiable {
    case history
    case values
    case manifest
    case hooks

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .history:  return "clock.arrow.circlepath"
        case .values:   return "slider.horizontal.3"
        case .manifest: return "doc.plaintext"
        case .hooks:    return "bolt.circle"
        }
    }
}

// MARK: - HelmDetailError

private enum HelmDetailError: Error, LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let name): return "Release '\(name)' not found in the cluster."
        }
    }
}
