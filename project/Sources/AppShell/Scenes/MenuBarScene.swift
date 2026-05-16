// Scenes/MenuBarScene.swift — app_shell bounded context
// DDD role: Scene root + popover presenter
// ADR ref: ADR-0022 (menu bar tray with live metrics), ADR-0034 (state-driven realtime UI)
//
// Note: ADR-0022 chose NSStatusItem+NSPopover for full popover fidelity. This file
// implements a MenuBarExtra scene as the SwiftUI scene hook; the popover UX and
// subscription lifecycle are owned by MenuBarTrayController (AppKit layer) once the
// domain agent lands the TrayRefreshScheduler aggregate. The MenuBarExtra scene
// provides the composition root until that bridge is wired.

import AppKit
import SwiftUI
import Dependencies
import ClusterConnectivity
import MetricsObservability
import SharedKernel

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

    /// Maps `HealthState` (ClusterConnectivity domain) to `TrayHealth` (AppShell UI).
    public init(from state: HealthState) {
        switch state {
        case .reachable:                    self = .healthy
        case .degraded:                     self = .degraded
        case .unreachable, .unauthorized,
             .forbidden:                    self = .unreachable
        case .unknown:                      self = .unknown
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
/// Cluster identity, health, and Prometheus metrics are fetched on each
/// 30-second refresh cycle. All async work runs in a structured `Task`
/// loop; the loop is cancelled when `stop()` is called.
@Observable
@MainActor
public final class MenuBarTrayViewModel {

    // MARK: Public state

    /// Current cluster summary powering the header badge.
    public private(set) var cluster: TrayClusterSummary = .placeholder
    /// Live metric tiles — 3 entries after first successful refresh.
    /// Empty only before the first cycle completes.
    public private(set) var metricTiles: [TrayMetricTile] = []
    /// True while a refresh is in flight.
    public private(set) var isRefreshing = false
    /// Formatted "last checked X" string; nil before first refresh.
    public private(set) var lastCheckedLabel: String?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubeconfigLoader) private var kubeconfigLoader

    @ObservationIgnored
    @Dependency(\.kubernetesApi) private var kubernetesApi

    @ObservationIgnored
    @Dependency(\.prometheusQuery) private var prometheusQuery

    @ObservationIgnored
    @Dependency(\.prometheusEndpointRepository) private var endpointRepository

    // MARK: Private

    private var refreshTask: Task<Void, Never>?

    /// Public initialiser — all ports injected via `@Dependency`.
    public init() {}

    // MARK: Lifecycle

    /// Starts the refresh loop. No-op when already running.
    ///
    /// Called from `popoverWillShow` / `.task` (ADR-0022).
    /// Each iteration runs every `intervalSeconds` (default 30 s).
    public func start(intervalSeconds: TimeInterval = 30) {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(intervalSeconds))
            }
        }
    }

    /// Cancels the refresh loop. Called from `popoverDidClose` / `.onDisappear`.
    public func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Refresh

    /// Executes one full refresh: active context + health probe + 3 metric tiles.
    ///
    /// Prometheus tiles are fetched when a configured endpoint is available;
    /// otherwise the tiles display placeholder dashes.
    public func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshCluster()
        await refreshMetrics()
        updateLastCheckedLabel()
    }

    // MARK: Private helpers

    private func refreshCluster() async {
        do {
            let config = try await kubeconfigLoader.load(from: KubeconfigPath("~/.kube/config"))
            let activeCtx = kubeconfigLoader.activeContext(in: config)
            let contextName = activeCtx?.name ?? config.currentContext ?? "—"
            let health: TrayHealth
            if let ctx = activeCtx {
                let status = try await kubernetesApi.probeHealth(clusterId: ClusterId(ctx.cluster))
                health = TrayHealth(from: status.state)
            } else {
                health = .unknown
            }
            cluster = TrayClusterSummary(
                contextName: contextName,
                health: health,
                lastCheckedISO: ISO8601DateFormatter().string(from: .now)
            )
        } catch {
            cluster = TrayClusterSummary(
                contextName: cluster.contextName,
                health: .unreachable,
                lastCheckedISO: ISO8601DateFormatter().string(from: .now)
            )
        }
    }

    private func refreshMetrics() async {
        do {
            let endpoints = try await endpointRepository.load()
            guard let endpoint = endpoints.first(where: { $0.status == .healthy }) ?? endpoints.first else {
                metricTiles = unavailableTiles()
                return
            }
            metricTiles = try await fetchMetricTiles(endpoint: endpoint)
        } catch {
            metricTiles = unavailableTiles()
        }
    }

    private func fetchMetricTiles(endpoint: PrometheusEndpoint) async throws -> [TrayMetricTile] {
        async let cpuResult = prometheusQuery.instantQuery(
            .instant(expr: "100 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100"),
            endpoint: endpoint
        )
        async let memResult = prometheusQuery.instantQuery(
            .instant(expr: "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100"),
            endpoint: endpoint
        )
        async let podsResult = prometheusQuery.instantQuery(
            .instant(expr: "count(kube_pod_info)"),
            endpoint: endpoint
        )
        let cpu  = Self.firstValue(from: try await cpuResult,  format: "%.1f")
        let mem  = Self.firstValue(from: try await memResult,  format: "%.1f")
        let pods = Self.firstValue(from: try await podsResult, format: "%.0f")
        return [
            TrayMetricTile(id: "cpu",  label: "CPU",    value: cpu,  unit: "%", systemImage: "cpu"),
            TrayMetricTile(id: "mem",  label: "Memory", value: mem,  unit: "%", systemImage: "memorychip"),
            TrayMetricTile(id: "pods", label: "Pods",   value: pods, unit: "",  systemImage: "square.3.layers.3d"),
        ]
    }

    private static func firstValue(from result: PromQueryResult, format: String) -> String {
        switch result {
        case .instantVector(let samples) where !samples.isEmpty:
            return String(format: format, samples[0].value)
        case .scalar(_, let value):
            return String(format: format, value)
        default:
            return "—"
        }
    }

    private func unavailableTiles() -> [TrayMetricTile] {
        [
            TrayMetricTile(id: "cpu",  label: "CPU",    value: "—", unit: "", systemImage: "cpu"),
            TrayMetricTile(id: "mem",  label: "Memory", value: "—", unit: "", systemImage: "memorychip"),
            TrayMetricTile(id: "pods", label: "Pods",   value: "—", unit: "", systemImage: "square.3.layers.3d"),
        ]
    }

    private func updateLastCheckedLabel() {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        lastCheckedLabel = "Checked " + formatter.localizedString(for: .now, relativeTo: .now)
    }

    /// Brings the main application window to the foreground.
    public func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
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
/// 2. Live metrics — 3 metric tiles (CPU, memory, pods).
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
                NotificationCenter.default.post(name: .palettePrefilter, object: nil, userInfo: ["query": "switch context"])
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
