// Scenes/MenuBarScene.swift — app_shell bounded context
// DDD role: Scene root + popover presenter
// ADR ref: ADR-0022 (menu bar tray with live metrics), ADR-0034 (state-driven realtime UI)
//
// Note: ADR-0022 chose NSStatusItem+NSPopover for full popover fidelity. This file
// implements a MenuBarExtra scene as the SwiftUI scene hook; the popover UX and
// subscription lifecycle are owned by MenuBarTrayController (AppKit layer) once the
// domain agent lands the TrayRefreshScheduler aggregate. The MenuBarExtra scene
// provides the composition root until that bridge is wired.

import SwiftUI

// MARK: - Placeholder read-models (replaced when domain-layer agent lands aggregates)

/// Minimal cluster health summary consumed by the tray popover.
///
/// Replaced by `ActiveContextReadModel` from `context_navigation` once the
/// parallel domain-layer agent delivers `Sources/AppShell/Domain/Aggregates/`.
public struct TrayClusterSummary: Sendable {
    /// Display name of the active kubeconfig context.
    public let contextName: String
    /// Coarse health signal driving the badge colour.
    public let health: TrayHealth
    /// ISO-8601 string of the last successful metric refresh.
    public let lastCheckedISO: String?

    public init(contextName: String, health: TrayHealth, lastCheckedISO: String? = nil) {
        self.contextName = contextName
        self.health = health
        self.lastCheckedISO = lastCheckedISO
    }

    /// Sentinel used before the first refresh completes.
    public static let placeholder = TrayClusterSummary(
        contextName: "—",
        health: .unknown,
        lastCheckedISO: nil
    )
}

/// Coarse health signal for the tray badge and icon overlay.
///
/// Maps to `statusHealthy` / `statusWarning` / `statusError` / `statusUnknown` design tokens.
public enum TrayHealth: String, Sendable {
    case healthy, degraded, unreachable, unknown

    var color: Color {
        switch self {
        case .healthy:     return .green
        case .degraded:    return .orange
        case .unreachable: return .red
        case .unknown:     return .gray
        }
    }

    var iconSymbol: String {
        switch self {
        case .healthy:     return "checkmark.circle.fill"
        case .degraded:    return "exclamationmark.circle.fill"
        case .unreachable: return "xmark.circle.fill"
        case .unknown:     return "questionmark.circle.fill"
        }
    }
}

/// Snapshot of a single live metric tile shown in the tray popover.
///
/// Replaced by `#TrayMetricWidget` from `contexts/app_shell/schemas/tray_metric_widget.cue`
/// once the domain aggregate layer is delivered.
public struct TrayMetricTile: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let unit: String
    public let systemImage: String

    public init(id: String, label: String, value: String, unit: String, systemImage: String) {
        self.id = id
        self.label = label
        self.value = value
        self.unit = unit
        self.systemImage = systemImage
    }
}

// MARK: - MenuBarTrayViewModel

/// View model for the tray popover — `@Observable` per ADR-0034.
///
/// Drives the `MenuBarPopoverView` from `@MainActor`-isolated properties.
/// All Prometheus and Kubernetes read-model work happens in detached Tasks;
/// results are posted back via `MainActor.run`.
@Observable
@MainActor
public final class MenuBarTrayViewModel {

    // MARK: Public state (read by views via granular observation tracking)

    /// Current cluster summary powering the header badge.
    public private(set) var cluster: TrayClusterSummary = .placeholder
    /// Live metric tiles; empty until first successful refresh.
    public private(set) var metricTiles: [TrayMetricTile] = []
    /// True while a refresh is in flight.
    public private(set) var isRefreshing = false
    /// Formatted "last checked X" string; nil before first refresh.
    public private(set) var lastCheckedLabel: String?

    // MARK: Private

    private var refreshTask: Task<Void, Never>?

    public init() {}

    // MARK: Lifecycle

    /// Called when the popover becomes visible (`popoverWillShow` equivalent).
    ///
    /// Starts the refresh loop. Each iteration fires every `refreshIntervalSeconds`
    /// (default 30 s per ADR-0022). Cancellation propagates when `stop()` is called.
    public func start(intervalSeconds: TimeInterval = 30) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    /// Called when the popover closes (`popoverDidClose` equivalent).
    ///
    /// Cancels the root Task; all child tasks are cancelled via structured concurrency.
    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Refresh

    /// Executes a single data refresh from read-model stubs.
    ///
    /// Replace the stub bodies below with real port calls once the domain layer lands:
    /// - `ActiveContextReadModel` from `context_navigation`
    /// - `PromQueryAdapter` port from `metrics_observability`
    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        // Stub: replaced by real domain port calls.
        // In production this calls PromQueryAdapter.queryInstant() off-actor
        // and posts the result back with MainActor.run.
        await Task.yield()

        cluster = TrayClusterSummary(
            contextName: cluster.contextName == "—" ? "default" : cluster.contextName,
            health: cluster.health,
            lastCheckedISO: ISO8601DateFormatter().string(from: .now)
        )

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        lastCheckedLabel = "Checked " + formatter.localizedString(for: .now, relativeTo: .now)

        // Stub metric tiles — replaced by PromQL results.
        metricTiles = [
            TrayMetricTile(id: "cpu",    label: "CPU",     value: "—",  unit: "%",   systemImage: "cpu"),
            TrayMetricTile(id: "mem",    label: "Memory",  value: "—",  unit: "GiB", systemImage: "memorychip"),
            TrayMetricTile(id: "pods",   label: "Pods",    value: "—",  unit: "",    systemImage: "square.3.layers.3d"),
        ]
    }

    /// Switch the active context — routes to `ContextSwitcher` once the domain lands.
    public func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.isMainWindow == false && $0.isVisible == false })?.makeKeyAndOrderFront(nil)
        for window in NSApp.windows where window.title != "" {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - K8sManagerMenuBarScene

/// SwiftUI `Scene` that installs the K8sManager tray icon in the macOS menu bar.
///
/// Uses `MenuBarExtra` with `.window` style. For the full NSPopover+NSStatusItem
/// experience specified in ADR-0022, wire `MenuBarTrayController` (AppKit bridge)
/// alongside this scene once the domain layer delivers `TrayRefreshScheduler`.
///
/// Activation shortcut: none — the tray icon is always present while the app runs.
public struct K8sManagerMenuBarScene: Scene {
    public init() {}

    public var body: some Scene {
        MenuBarExtra("K8sManager", systemImage: "cube.transparent") {
            MenuBarPopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - MenuBarPopoverView

/// Content view rendered inside the `MenuBarExtra` window.
///
/// Sections (per ADR-0022 § Popover Content Layout):
/// 1. Header — active context name + cluster health badge + last-checked label.
/// 2. Live metrics — up to 5 metric tiles (CPU, memory, pods…).
/// 3. Quick actions — Open Main Window, Switch Context, Quit.
@MainActor
public struct MenuBarPopoverView: View {

    @State private var viewModel = MenuBarTrayViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            metricsSection
            Divider()
            quickActionsSection
        }
        .frame(width: 320)
        .task {
            viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.cluster.health.iconSymbol)
                    .foregroundStyle(viewModel.cluster.health.color)
                    .accessibilityHidden(true)
                Text(viewModel.cluster.contextName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing metrics")
                }
            }
            if let label = viewModel.lastCheckedLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Active cluster \(viewModel.cluster.contextName), "
            + "health \(viewModel.cluster.health.rawValue)"
        )
    }

    // MARK: Metrics

    private var metricsSection: some View {
        Group {
            if viewModel.metricTiles.isEmpty {
                emptyMetricsView
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 8
                ) {
                    ForEach(viewModel.metricTiles) { tile in
                        metricTileView(tile)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    private var emptyMetricsView: some View {
        VStack(spacing: 4) {
            Text("No metrics available")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Configure a Prometheus endpoint in Settings")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func metricTileView(_ tile: TrayMetricTile) -> some View {
        VStack(spacing: 4) {
            Image(systemName: tile.systemImage)
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(tile.value + (tile.unit.isEmpty ? "" : " \(tile.unit)"))
                .font(.callout.monospacedDigit())
                .lineLimit(1)
            Text(tile.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.label) \(tile.value) \(tile.unit)")
    }

    // MARK: Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 0) {
            quickActionButton(title: "Open Main Window", systemImage: "macwindow") {
                viewModel.openMainWindow()
            }
            quickActionButton(title: "Switch Context…", systemImage: "arrow.triangle.branch") {
                // Routes to palette pre-filtered on "switch context" once ADR-0023 wiring lands.
                viewModel.openMainWindow()
            }
            Divider().padding(.horizontal, 16)
            quickActionButton(title: "Quit K8sManager", systemImage: "power", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
        .padding(.bottom, 4)
    }

    private func quickActionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityLabel(title)
    }
}

// MARK: - AppKit import for NSApp usage

import AppKit
