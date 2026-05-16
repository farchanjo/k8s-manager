// Views/Terminal/ExecToolbar.swift — app_shell bounded context
// DDD role: View — toolbar for exec and node-debug terminal tabs
// ADR ref: ADR-0017 (terminal sessions)

import SwiftUI
import AppKit

// MARK: - ExecToolbar

/// Toolbar displayed above the terminal canvas in exec and node-debug tabs.
///
/// Features:
/// - Container picker (shown when `availableContainers` has > 1 entry)
/// - Connection state indicator with colour coding
/// - Reconnect button (visible only when disconnected / failed)
/// - Clear output button
/// - Copy all output button
/// - Ctrl+C / Ctrl+D quick-send buttons
public struct ExecToolbar: View {

    // MARK: Properties

    let container: String?
    let availableContainers: [String]
    let onContainerChange: @MainActor (String) -> Void
    let onReconnect: @MainActor () -> Void
    let onClose: @MainActor () -> Void
    let connectionState: ExecConnectionState
    let output: String
    let onClear: @MainActor () -> Void
    let onCtrlC: @MainActor () -> Void
    let onCtrlD: @MainActor () -> Void

    // MARK: Init

    public init(
        container: String?,
        availableContainers: [String],
        onContainerChange: @escaping @MainActor (String) -> Void,
        onReconnect: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void,
        connectionState: ExecConnectionState,
        output: String = "",
        onClear: @escaping @MainActor () -> Void = {},
        onCtrlC: @escaping @MainActor () -> Void = {},
        onCtrlD: @escaping @MainActor () -> Void = {}
    ) {
        self.container = container
        self.availableContainers = availableContainers
        self.onContainerChange = onContainerChange
        self.onReconnect = onReconnect
        self.onClose = onClose
        self.connectionState = connectionState
        self.output = output
        self.onClear = onClear
        self.onCtrlC = onCtrlC
        self.onCtrlD = onCtrlD
    }

    // MARK: Body

    public var body: some View {
        HStack(spacing: 8) {
            containerPicker
            Divider().frame(height: 20)
            connectionIndicator
            reconnectButton
            Spacer()
            ctrlCButton
            ctrlDButton
            Divider().frame(height: 20)
            clearButton
            copyButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: Private subviews

    @ViewBuilder
    private var containerPicker: some View {
        if availableContainers.count > 1 {
            Picker("Container", selection: pickerBinding) {
                ForEach(availableContainers, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 160)
        } else if let name = container {
            Label(name, systemImage: "shippingbox")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var pickerBinding: Binding<String> {
        Binding(
            get: { container ?? "" },
            set: { onContainerChange($0) }
        )
    }

    private var connectionIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(stateLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var indicatorColor: Color {
        switch connectionState {
        case .connecting, .reconnecting: return .orange
        case .connected:                 return .green
        case .disconnected:              return .gray
        case .failed:                    return .red
        }
    }

    private var stateLabel: String {
        switch connectionState {
        case .connecting:               return "Connecting…"
        case .connected:                return "Connected"
        case .reconnecting:             return "Reconnecting…"
        case .disconnected(let reason): return reason.map { "Disconnected: \($0)" } ?? "Disconnected"
        case .failed(let msg):          return "Failed: \(msg)"
        }
    }

    @ViewBuilder
    private var reconnectButton: some View {
        switch connectionState {
        case .disconnected, .failed:
            Button(action: { onReconnect() }) {
                Label("Reconnect", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Reconnect to the container")
        default:
            EmptyView()
        }
    }

    private var ctrlCButton: some View {
        Button(action: { onCtrlC() }) {
            Text("^C")
                .font(.caption.monospaced())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Send Ctrl+C (interrupt)")
    }

    private var ctrlDButton: some View {
        Button(action: { onCtrlD() }) {
            Text("^D")
                .font(.caption.monospaced())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Send Ctrl+D (EOF / logout)")
    }

    private var clearButton: some View {
        Button(action: { onClear() }) {
            Label("Clear", systemImage: "trash")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("Clear terminal output")
    }

    private var copyButton: some View {
        Button(action: copyOutput) {
            Label("Copy", systemImage: "doc.on.doc")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help("Copy all output to clipboard")
    }

    private func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }
}
