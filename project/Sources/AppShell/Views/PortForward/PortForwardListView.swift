// Views/PortForward/PortForwardListView.swift — app_shell bounded context
// DDD role: View — Port-forward session list (Onda 3)
// ADR ref: ADR-0014 (lifecycle, loopback warning), ADR-0050 (tab system)

import SwiftUI
import SharedKernel

// MARK: - PortForwardListView

/// Top-level view for the port-forward session list tab.
///
/// Replaces the earlier `PortForwardingView` placeholder.
/// Renders a `Table` of active and recently-closed port-forward sessions,
/// a toolbar for creating new forwards, and a sheet for the creation wizard.
public struct PortForwardListView: View {

    public let clusterId: ClusterId

    @State private var viewModel = PortForwardListViewModel()

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    public var body: some View {
        VStack(spacing: 0) {
            listToolbar
            Divider()
            tableContent
        }
        .sheet(isPresented: $viewModel.showingNewForwardSheet) {
            NewPortForwardSheet(
                clusterId: clusterId,
                onCreated: { Task { await viewModel.reload() } }
            )
        }
        .task { await viewModel.start(clusterId: clusterId) }
    }

    // MARK: Private views

    private var listToolbar: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.showingNewForwardSheet = true
            } label: {
                Label("New Forward", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button {
                Task { await viewModel.reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Spacer()

            if !viewModel.sessions.isEmpty {
                Text("\(viewModel.sessions.count) tunnel\(viewModel.sessions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var tableContent: some View {
        switch viewModel.loadState {
        case .idle, .loading where viewModel.sessions.isEmpty:
            ProgressView("Loading port forwards…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error):
            errorView(error)
        default:
            sessionTable
        }
    }

    private var sessionTable: some View {
        Table(viewModel.sessions, selection: $viewModel.selectedId) {
            TableColumn("Target") { row in
                Label(row.targetName, systemImage: row.targetIcon)
            }
            TableColumn("Local") { row in
                Text("\(row.localPort)").monospacedDigit()
            }
            TableColumn("→") { _ in
                Text("→").foregroundStyle(.secondary)
            }
            .width(20)
            TableColumn("Remote") { row in
                Text("\(row.remotePort)").monospacedDigit()
            }
            TableColumn("Status") { row in
                PortForwardStatusBadge(status: row.status)
            }
            TableColumn("Bytes I/O") { row in
                Text(row.bytesFormatted)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            TableColumn("Age") { row in
                Text(row.age)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TableColumn("Actions") { row in
                rowActions(row)
            }
            .width(90)
        }
    }

    private func rowActions(_ row: PortForwardRow) -> some View {
        HStack(spacing: 4) {
            Button { viewModel.openInBrowser(row) } label: {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("Open in browser")

            Button { viewModel.copyURL(row) } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy URL")

            Button(role: .destructive) {
                Task { await viewModel.stop(row) }
            } label: {
                Image(systemName: "stop.circle")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .help("Stop tunnel")
        }
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(error.localizedDescription)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.reload() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - PortForwardStatusBadge

/// Compact status indicator used in the port-forward session table.
struct PortForwardStatusBadge: View {

    let status: ForwardStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.symbolName)
                .foregroundStyle(accent)
                .font(.caption)
            Text(status.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(accent)
        }
    }

    private var accent: Color {
        switch status {
        case .active:       return .green
        case .starting:     return .yellow
        case .reconnecting: return .orange
        case .degraded:     return .orange
        case .stopped:      return .secondary
        case .failed:       return .red
        }
    }
}
