// Views/ClusterStrip/ClusterStripView.swift — app_shell bounded context
// ADR ref: ADR-0051 (vertical cluster strip, left edge of AppShell)

import SwiftUI
import SharedKernel

// MARK: - ClusterStripView

/// Fixed-width (56 pt) vertical strip shown at the left edge of the window.
///
/// Contains one ``ClusterAvatarButton`` per pinned cluster and a `+` button at
/// the bottom to open ``ClusterPickerSheet``. The view is always visible and
/// cannot be collapsed (ADR-0051).
///
/// State is owned by a ``ClusterStripViewModel`` backed by ``ClusterStripActor``.
public struct ClusterStripView: View {

    // MARK: State

    @State private var viewModel = ClusterStripViewModel()

    // MARK: Init

    public init() {}

    /// Dependency-injection seam used in tests and Xcode Previews.
    internal init(viewModel: ClusterStripViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 6) {
            ForEach(viewModel.pins) { pin in
                ClusterAvatarButton(
                    pin: pin,
                    isActive: pin.clusterId == viewModel.activeClusterId
                )
                .onTapGesture {
                    Task { await viewModel.activate(pin.clusterId) }
                }
                .contextMenu { unpinMenu(for: pin) }
            }
            addButton
            Spacer()
        }
        .padding(.vertical, 8)
        .frame(width: 56)
        .background(.regularMaterial)
        .task { await viewModel.start() }
        .sheet(isPresented: $viewModel.showingClusterPicker) { pickerSheet }
    }

    // MARK: Sub-views

    private var addButton: some View {
        Button {
            viewModel.showingClusterPicker = true
        } label: {
            Image(systemName: "plus")
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Pin a cluster")
    }

    @ViewBuilder
    private func unpinMenu(for pin: ClusterStripPin) -> some View {
        Button("Unpin") {
            Task { await viewModel.unpin(pin.clusterId) }
        }
    }

    private var pickerSheet: some View {
        ClusterPickerSheet(
            pinnedIds: Set(viewModel.pins.map(\.clusterId))
        ) { clusterId, displayName in
            try await viewModel.pin(clusterId, displayName: displayName)
        }
    }
}
