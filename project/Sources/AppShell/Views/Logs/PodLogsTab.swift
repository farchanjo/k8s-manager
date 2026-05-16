// Views/Logs/PodLogsTab.swift — app_shell bounded context
// DDD role: View — pod log streaming tab root
// ADR ref: ADR-0050 (tab system), Onda 3

import SwiftUI
import SharedKernel

// MARK: - PodLogsTab

/// Root view for the `.logs` tab case.
///
/// Composes `LogsToolbar` and `LogsScrollView` and wires them
/// to a single `PodLogsViewModel` owned by this view.
public struct PodLogsTab: View {

    // MARK: Inputs

    public let clusterId: ClusterId
    public let podRef: ResourceRef
    public let container: String?

    // MARK: State

    @State private var viewModel = PodLogsViewModel()

    // MARK: Init

    public init(clusterId: ClusterId, podRef: ResourceRef, container: String?) {
        self.clusterId = clusterId
        self.podRef = podRef
        self.container = container
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            LogsToolbar(viewModel: viewModel)
            Divider()
            LogsScrollView(viewModel: viewModel)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            await viewModel.start(clusterId: clusterId, podRef: podRef, container: container)
        }
    }
}
