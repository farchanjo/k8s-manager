// Views/Detail/ResourceDetailDrawer.swift — app_shell bounded context
// DDD role: View — slide-in detail drawer composition root (Onda 2)
// ADR ref: ADR-0021 (detail drawer), ADR-0050 (tab system)

import SwiftUI
import SharedKernel

// MARK: - ResourceDetailDrawer

/// Slide-in detail drawer shown when a row is selected in any resource list.
///
/// Composed of a sticky `DetailHeader`, a scrollable body with five named
/// sections (Metrics, Properties, Containers, Volumes, Events), and a
/// fixed 480-point width. Presented via `.inspector(isPresented:)` on macOS 14+.
///
/// The parent view owns `selectedRef: ResourceRef?`; setting it to a non-nil
/// value opens this drawer. The drawer calls `onOpenTab` and `onDismiss`
/// to propagate navigation events upward.
@MainActor
public struct ResourceDetailDrawer: View {

    // MARK: Input

    public let clusterId: ClusterId
    public let ref: ResourceRef
    /// Called when an action inside the drawer requests a new tab.
    public let onOpenTab: (DocumentTab) -> Void
    /// Called when the drawer should close (e.g. the X button).
    public let onDismiss: () -> Void

    // MARK: Private state

    @State private var viewModel = ResourceDetailViewModel()

    // MARK: Init

    public init(
        clusterId: ClusterId,
        ref: ResourceRef,
        onOpenTab: @escaping (DocumentTab) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.clusterId = clusterId
        self.ref = ref
        self.onOpenTab = onOpenTab
        self.onDismiss = onDismiss
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            DetailHeader(
                kind: ref.kind.kind,
                title: ref.name,
                onEdit: { viewModel.openEditor(clusterId: clusterId, ref: ref) },
                onShell: { viewModel.openShell(clusterId: clusterId, ref: ref) },
                onRestart: { Task { await viewModel.confirmRestart(clusterId: clusterId, ref: ref) } },
                onDelete: { Task { await viewModel.confirmDelete(clusterId: clusterId, ref: ref) } },
                onClose: viewModel.close
            )
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    MetricsSection(clusterId: clusterId, ref: ref, viewModel: viewModel)
                    Divider()
                    PropertiesSection(
                        properties: viewModel.properties,
                        onOpenRef: { linkedRef in
                            onOpenTab(.resourceDetail(clusterId: clusterId, ref: linkedRef))
                        }
                    )
                    Divider()
                    ContainersSection(
                        containers: viewModel.containers,
                        onLogs: { container in
                            viewModel.openLogs(clusterId: clusterId, ref: ref, container: container)
                        },
                        onExec: { container in
                            viewModel.openShell(clusterId: clusterId, ref: ref, container: container)
                        }
                    )
                    Divider()
                    VolumesSection(volumes: viewModel.volumes)
                    Divider()
                    EventsSection(
                        events: viewModel.events,
                        onViewAll: {
                            onOpenTab(.events(
                                clusterId: clusterId,
                                scope: .resource(ref)
                            ))
                        }
                    )
                }
                .padding(16)
            }
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .task(id: ref) {
            viewModel.onOpenTab = onOpenTab
            viewModel.onClose = onDismiss
            await viewModel.start(clusterId: clusterId, ref: ref)
        }
    }
}
