// Views/Logs/LogsToolbar.swift — app_shell bounded context
// DDD role: View — log streaming controls toolbar
// ADR ref: Onda 3

import SwiftUI
import ResourceBrowser
import SharedKernel

// MARK: - LogsToolbar

/// Toolbar above the log scroll view.
///
/// Controls: follow toggle, wrap toggle, tail-lines picker, timestamps
/// toggle, container picker, severity filter chips, search bar,
/// pause/resume, clear buffer, and export.
public struct LogsToolbar: View {

    @Bindable var viewModel: PodLogsViewModel

    public init(viewModel: PodLogsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 8) {
            followToggle
            wrapToggle
            timestampsToggle
            Divider().frame(height: 20)
            tailLinesPicker
            if viewModel.availableContainers.count > 1 {
                containerPicker
            }
            Divider().frame(height: 20)
            searchBar
            severityChips
            Spacer()
            streamControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: Private sub-views

    private var followToggle: some View {
        Toggle(isOn: $viewModel.follow) {
            Label("Follow", systemImage: "arrow.down.to.line")
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Auto-scroll to the newest log line")
    }

    private var wrapToggle: some View {
        Toggle(isOn: $viewModel.wrap) {
            Label("Wrap", systemImage: "text.word.spacing")
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Word-wrap long lines")
    }

    private var timestampsToggle: some View {
        Toggle(isOn: $viewModel.showTimestamps) {
            Label("Timestamps", systemImage: "clock")
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Show RFC 3339 timestamp prefix")
    }

    private var tailLinesPicker: some View {
        Picker("Tail", selection: $viewModel.tailLines) {
            Text("100").tag(Optional(100))
            Text("500").tag(Optional(500))
            Text("1 000").tag(Optional(1_000))
            Text("5 000").tag(Optional(5_000))
            Text("All").tag(Optional<Int>.none)
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .help("Number of historical lines to retrieve")
    }

    private var containerPicker: some View {
        Picker("Container", selection: $viewModel.selectedContainer) {
            Text("All").tag(Optional<String>.none)
            ForEach(viewModel.availableContainers, id: \.self) { name in
                Text(name).tag(Optional(name))
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .help("Select a specific container")
    }

    private var searchBar: some View {
        TextField("Search…", text: $viewModel.searchQuery)
            .textFieldStyle(.roundedBorder)
            .frame(width: 160)
            .controlSize(.small)
    }

    private var severityChips: some View {
        HStack(spacing: 4) {
            ForEach(LogSeverity.allCases, id: \.self) { sev in
                SeverityChip(severity: sev, isActive: viewModel.severityFilter.contains(sev)) {
                    if viewModel.severityFilter.contains(sev) {
                        viewModel.severityFilter.remove(sev)
                    } else {
                        viewModel.severityFilter.insert(sev)
                    }
                }
            }
        }
    }

    private var streamControls: some View {
        HStack(spacing: 4) {
            if viewModel.isPaused {
                Button { Task { await viewModel.resume() } } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.green)
            } else {
                Button { viewModel.pause() } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button { viewModel.clearBuffer() } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Clear the log buffer")

            Button {
                Task {
                    if let url = await viewModel.exportLogs() {
                        NSWorkspace.shared.open(url)
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Export logs to a .log file")
        }
    }
}

// MARK: - SeverityChip

/// Compact toggle button for a single `LogSeverity` level.
private struct SeverityChip: View {

    let severity: LogSeverity
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(severity.rawValue.uppercased())
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? severity.color : .secondary)
        .controlSize(.mini)
    }
}
