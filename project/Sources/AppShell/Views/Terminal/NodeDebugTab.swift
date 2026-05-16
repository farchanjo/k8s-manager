// Views/Terminal/NodeDebugTab.swift — app_shell bounded context
// DDD role: View — node debug terminal tab composition
// ADR ref: ADR-0017 (terminal sessions), ADR-0012 (mutating ops)

import SwiftUI
import SharedKernel

// MARK: - NodeDebugTab

/// Composed terminal tab for `nodes/debug` sessions.
///
/// Creates an ephemeral debug Pod on the target node via `NodeDebugViewModel`,
/// then wires `ExecToolbar` + `TerminalView`. The ephemeral Pod is deleted
/// cooperatively when the tab is closed or the view disappears.
public struct NodeDebugTab: View {

    // MARK: Properties

    public let clusterId: ClusterId
    public let nodeRef: ResourceRef

    @State private var viewModel = NodeDebugViewModel()

    // MARK: Init

    public init(clusterId: ClusterId, nodeRef: ResourceRef) {
        self.clusterId = clusterId
        self.nodeRef = nodeRef
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            ExecToolbar(
                container: viewModel.ephemeralPodName ?? nodeRef.name,
                availableContainers: [],
                onContainerChange: { _ in },
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
            await viewModel.connect(clusterId: clusterId, nodeRef: nodeRef)
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
