// Views/Terminal/PodExecTab.swift — app_shell bounded context
// DDD role: View — pod exec terminal tab composition
// ADR ref: ADR-0017 (terminal sessions), ADR-0050 (tab system)

import SwiftUI
import SharedKernel

// MARK: - PodExecTab

/// Composed terminal tab for `pods/exec` sessions.
///
/// Wires `PodExecViewModel` → `ExecToolbar` + `TerminalView` and manages
/// the session lifecycle within the tab's `.task` / `.onDisappear` scope.
public struct PodExecTab: View {

    // MARK: Properties

    public let clusterId: ClusterId
    public let podRef: ResourceRef
    public let container: String?

    @State private var viewModel = PodExecViewModel()

    // MARK: Init

    public init(clusterId: ClusterId, podRef: ResourceRef, container: String?) {
        self.clusterId = clusterId
        self.podRef = podRef
        self.container = container
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            ExecToolbar(
                container: viewModel.selectedContainer,
                availableContainers: viewModel.availableContainers,
                onContainerChange: { name in
                    Task { await viewModel.switchContainer(name) }
                },
                onReconnect: {
                    Task { await viewModel.reconnect() }
                },
                onClose: { viewModel.close() },
                connectionState: viewModel.connectionState,
                output: viewModel.outputBuffer,
                onClear: { viewModel.outputBuffer = "" },
                onCtrlC: { viewModel.sendInput("\u{03}") },
                onCtrlD: { viewModel.sendInput("\u{04}") }
            )
            Divider()
            terminalCanvas
        }
        .task {
            await viewModel.connect(
                clusterId: clusterId,
                podRef: podRef,
                container: container
            )
        }
        .onDisappear {
            Task { await viewModel.disconnect() }
        }
    }

    // MARK: Private

    private var terminalCanvas: some View {
        GeometryReader { geo in
            TerminalView(
                output: viewModel.outputBuffer,
                onInput: { text in viewModel.sendInput(text) },
                onResize: { cols, rows in
                    viewModel.resizeTerminal(cols: cols, rows: rows)
                },
                fontFamily: "SF Mono",
                fontSize: 13
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
