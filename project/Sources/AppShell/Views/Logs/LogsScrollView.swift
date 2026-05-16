// Views/Logs/LogsScrollView.swift — app_shell bounded context
// DDD role: View — scrollable, auto-following log line list
// ADR ref: Onda 3

import SwiftUI
import ResourceBrowser
import SharedKernel

// MARK: - LogsScrollView

/// Scrollable container for log lines.
///
/// Uses a `ScrollViewReader` to implement auto-follow: when `follow` is
/// `true` and new lines arrive the view animates to the last line's id.
/// Lines are rendered via `LazyVStack` so only visible rows are materialized.
public struct LogsScrollView: View {

    @Bindable var viewModel: PodLogsViewModel

    public init(viewModel: PodLogsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let filtered = viewModel.filteredLines
        let showContainerBadge = viewModel.availableContainers.count > 1

        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { line in
                            LogLineView(
                                line: line,
                                showTimestamp: viewModel.showTimestamps,
                                showContainerBadge: showContainerBadge,
                                searchQuery: viewModel.searchQuery
                            )
                            .lineLimit(viewModel.wrap ? nil : 1)
                            .truncationMode(.tail)
                            .id(line.id)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: viewModel.lines.count) {
                guard viewModel.follow, let lastId = viewModel.filteredLines.last?.id else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    // MARK: Private

    private var emptyState: some View {
        Group {
            if viewModel.loadState.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Connecting to log stream…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                Text("No log lines.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
