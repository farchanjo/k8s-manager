// Views/Events/EventsTimelineView.swift — app_shell bounded context
// DDD role: View — cluster-wide events timeline tab (Onda 3)
// ADR ref: ADR-0050 (tab system), ADR-0034 (state-driven realtime UI)

import SwiftUI
import SharedKernel

// MARK: - EventsTimelineView

/// Full-featured events timeline tab: live grouped scroll + toolbar + summary bar.
///
/// Replaces the simpler `EventsListView` (which is preserved for backward
/// compatibility) as the target for `.events` tabs opened from `ActiveTabContentView`.
@MainActor
public struct EventsTimelineView: View {

    // MARK: Input

    public let clusterId: ClusterId
    public let scope: EventScope?

    // MARK: Private state

    @State private var viewModel = EventsTimelineViewModel()

    // MARK: Init

    public init(clusterId: ClusterId, scope: EventScope? = nil) {
        self.clusterId = clusterId
        self.scope = scope
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            EventsToolbar(
                typeFilter: Binding(get: { viewModel.typeFilter }, set: { viewModel.typeFilter = $0 }),
                reasonFilter: Binding(get: { viewModel.reasonFilter }, set: { viewModel.reasonFilter = $0 }),
                namespaceFilter: Binding(get: { viewModel.namespaceFilter }, set: { viewModel.namespaceFilter = $0 }),
                ageFilter: Binding(get: { viewModel.ageFilter }, set: { viewModel.ageFilter = $0 }),
                searchQuery: Binding(get: { viewModel.searchQuery }, set: { viewModel.searchQuery = $0 }),
                availableReasons: viewModel.availableReasons,
                availableNamespaces: viewModel.availableNamespaces,
                isPaused: viewModel.isPaused,
                onClear: viewModel.clearFilters,
                onPause: viewModel.pause,
                onResume: { Task { await viewModel.resume() } },
                onExport: { Task { _ = await viewModel.exportEvents() } }
            )
            Divider()
            EventsSummaryBar(
                totalCount: viewModel.events.count,
                warningCount: viewModel.warningCount,
                normalCount: viewModel.normalCount,
                lastUpdated: viewModel.lastUpdated
            )
            Divider()
            eventsScroll
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await viewModel.start(clusterId: clusterId, scope: scope) }
    }

    // MARK: Private views

    @ViewBuilder
    private var eventsScroll: some View {
        if viewModel.filteredEvents.isEmpty {
            ContentUnavailableView(
                "No events",
                systemImage: "calendar.badge.clock",
                description: Text("No events match the current filters.")
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 4, pinnedViews: .sectionHeaders) {
                    ForEach(viewModel.groupedEvents, id: \.key) { group in
                        Section {
                            ForEach(group.events) { event in
                                EventTimelineRow(
                                    event: event,
                                    isSelected: viewModel.selectedEventId == event.id,
                                    onSelect: { viewModel.selectedEventId = $0.id }
                                )
                            }
                        } header: {
                            EventGroupHeader(groupKey: group.key, count: group.events.count)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }
}
