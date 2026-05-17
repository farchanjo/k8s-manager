// AppShell.swift — NavigationSplitView shell
// Bounded context: app_shell (per ADR-0005)
// ADR ref: ADR-0022 (menu bar tray), ADR-0023 (command palette + shortcuts),
//          ADR-0032 (toasts), ADR-0050 (tab bar), ADR-0051 (Lens-style layout),
//          ADR-0073 (inspector trailing column)
import Dependencies
import Foundation
import SharedKernel
import SwiftUI

/// Namespace marker for the AppShell bounded context.
///
/// Domain types, ports, and actors land under this enum in subsequent rounds.
/// This file exists so the target compiles cleanly under Swift 6 strict concurrency.
public enum AppShell: Sendable {
    /// Build identifier — bumped manually until CI emits this.
    public static let moduleVersion = "0.0.1-skeleton"
}

// MARK: - K8sManagerRootScene

/// Root SwiftUI scene graph presenting a `NavigationSplitView` shell plus:
/// - `K8sManagerMenuBarScene` — tray icon (ADR-0022).
/// - `.commands { K8sManagerCommands() }` — global keyboard bindings (ADR-0023).
/// - `ToastStackView` overlay — operation feedback (ADR-0032).
/// - `CommandPaletteOverlay` overlay — universal command entry (ADR-0023).
///
/// Wired by the `K8sManagerApp` composition root. All feature panels
/// are driven by `Feature.allCases` through the sidebar selection binding.
public struct K8sManagerRootScene: Scene {

    // Shared view models lifted to scene scope so Commands and the main window
    // reference the same instances.
    @State private var paletteViewModel = CommandPaletteViewModel()
    @State private var toastViewModel = ToastStackViewModel()
    @State private var selectedFeature: Feature? = .clusters

    /// Domain-layer aggregate and dependencies constructed once at scene init.
    ///
    /// `toastAggregate` backs `ToastDomainEmitter` (domain port) independently of
    /// the view-layer `ToastStackViewModel` — they serve different concerns:
    /// domain emitter writes to the aggregate actor; the view model drives the UI stack.
    private let appShellDeps: AppShellDependencies

    /// Designated init.
    /// - Parameters:
    ///   - codeEditor: Concrete `CodeEditorPort` injected by the composition
    ///     root (`K8sManagerApp` passes `CodeEditorViewAdapter()`). Defaults to
    ///     `UnimplementedCodeEditor()` so previews and tests can instantiate
    ///     the scene without the adapter target.
    ///   - openTabsActor: The shared `OpenTabsActor` instance, owned by the
    ///     composition root. SwiftUI views and `SidebarTreeViewModel` read the
    ///     same actor via `AppShellDependencies` / `\.openTabs` — wiring both
    ///     pathways from one source prevents tab-bar / sidebar drift.
    public init(
        codeEditor: any CodeEditorPort = UnimplementedCodeEditor(),
        openTabsActor: OpenTabsActor? = nil,
        workspaceTabsActor: WorkspaceTabsActor? = nil,
        navigationHistoryActor: NavigationHistoryActor? = nil,
        dockedTerminalPaneActor: DockedTerminalPaneActor? = nil,
        dockedYAMLEditorPaneActor: DockedYAMLEditorPaneActor? = nil,
        inspectorViewModel: ResourceInspectorViewModel? = nil
    ) {
        let toastAggregate = ToastStackAggregate(
            initial: DomainToastStack(id: UUID().uuidString)
        )
        // Default workspace tabs actor — composition root may override with a
        // pre-hydrated instance. Falls back to the default persistence URL so
        // the persistent Welcome tab works in previews and tests without
        // bootstrap wiring.
        let resolvedWorkspaceTabs = workspaceTabsActor ?? WorkspaceTabsActor(
            persistenceURL: ApplicationPaths.workspaceTabsURL
        )
        // Default navigation history actor — composition root may override with a
        // pre-hydrated instance for testing. Falls back to the canonical ADR-0065
        // persistence path so cold-launch restoration works out of the box.
        let resolvedNavHistory = navigationHistoryActor ?? NavigationHistoryActor(
            persistenceURL: ApplicationPaths.navigationHistoryURL
        )
        // Default docked pane actors — composition root may override with
        // pre-constructed instances that survive scene re-init cycles.
        let resolvedTerminalPane = dockedTerminalPaneActor ?? DockedTerminalPaneActor(
            persistenceURL: ApplicationPaths.dockedTerminalPaneURL
        )
        let resolvedYAMLPane = dockedYAMLEditorPaneActor ?? DockedYAMLEditorPaneActor(
            persistenceURL: ApplicationPaths.dockedYAMLEditorPaneURL
        )
        // Inspector view model — single instance per window. Wave 3 creates it
        // unconditionally; future waves may allow nil when the feature is toggled off.
        let resolvedInspector = inspectorViewModel ?? ResourceInspectorViewModel()
        appShellDeps = AppShellDependencies(
            translationCatalog: BundleTranslationCatalog(bundle: .main),
            toastEmitter: ToastDomainEmitter(aggregate: toastAggregate),
            localePreference: InMemoryLocalePreferenceStore(),
            openTabsActor: openTabsActor,
            workspaceTabsActor: resolvedWorkspaceTabs,
            navigationHistoryActor: resolvedNavHistory,
            codeEditor: codeEditor,
            dockedTerminalPaneActor: resolvedTerminalPane,
            dockedYAMLEditorPaneActor: resolvedYAMLPane,
            inspectorViewModel: resolvedInspector
        )
    }

    public var body: some Scene {
        WindowGroup {
            AppShellView(
                selectedFeature: $selectedFeature,
                paletteViewModel: paletteViewModel,
                toastViewModel: toastViewModel
            )
            .appShellDependencies(appShellDeps)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentSize)
        // Apple HIG window chrome — ADR-0072 §"Change 1: window toolbar style".
        // `.unifiedCompact(showsTitle: false)` collapses the title bar and the
        // toolbar row into a single dense strip and removes the redundant
        // "K8sManager" title text (already in the app menu). This is Band 1 of
        // the three-band ceiling established by ADR-0072.
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            K8sManagerCommands(
                isPaletteVisible: Binding(
                    get: { paletteViewModel.isVisible },
                    set: { newValue in
                        if newValue { paletteViewModel.open() } else { paletteViewModel.dismiss() }
                    }
                ),
                selectedFeature: $selectedFeature
            )
        }

        // Menu bar tray (ADR-0022).
        K8sManagerMenuBarScene()
            .appShellDependencies(appShellDeps)
    }
}

// MARK: - AppShellView

/// Top-level shell view — sidebar + detail layout + overlays.
///
/// Receives `paletteViewModel` and `toastViewModel` from the scene so both
/// overlays share the same state as `K8sManagerCommands`.
@MainActor
public struct AppShellView: View {

    @Binding var selectedFeature: Feature?
    var paletteViewModel: CommandPaletteViewModel
    var toastViewModel: ToastStackViewModel

    public init(
        selectedFeature: Binding<Feature?>,
        paletteViewModel: CommandPaletteViewModel,
        toastViewModel: ToastStackViewModel
    ) {
        self._selectedFeature = selectedFeature
        self.paletteViewModel = paletteViewModel
        self.toastViewModel = toastViewModel
    }

    @Environment(\.appShellDependencies) private var deps

    /// Active cluster id mirrored from `ClusterStripActor` so the canvas
    /// header can render the global namespace picker for the right cluster.
    @State private var activeClusterId: ClusterId?

    /// Cluster-strip visibility per ADR-0072 §"Change 4". Persisted via
    /// `@AppStorage` so the operator's preference survives relaunches. The
    /// canonical home for this flag is `WindowLayout.mainWindow
    /// .clusterStripVisible`; once the WindowLayout persistence pipeline is
    /// wired end-to-end the `@AppStorage` shim is replaced by reading the
    /// aggregate. The shim defaults to `true` to match the aggregate default.
    @AppStorage("appShell.clusterStripVisible") private var clusterStripVisible = true

    public var body: some View {
        HStack(spacing: 0) {
            // Cluster strip (ADR-0051) — operator-toggleable per ADR-0072.
            // Default visible so the one-click cluster-switch UX is preserved
            // for existing operators; collapsible via the window toolbar
            // button (`Cmd-Shift-K` shortcut wired in K8sManagerCommands).
            if clusterStripVisible {
                ClusterStripView()
            }

            // NavigationSplitView: hierarchical sidebar tree | canvas (ADR-0050/0051)
            // The canvas detail column carries `.inspector(isPresented:)` per
            // ADR-0073 §"NavigationSplitView extension to three columns".
            NavigationSplitView {
                sidebarTree
            } detail: {
                canvas
            }
            // Propagate the inspector view model through the SwiftUI environment
            // so resource list views can call `setSelection(_:)` without prop-drilling.
            .resourceInspector(deps.inspectorViewModel)
            .k8sKeyboardShortcuts(
                selectedFeature: $selectedFeature,
                paletteViewModel: paletteViewModel,
                toastViewModel: toastViewModel
            )
            // Window toolbar — Band 1 of ADR-0072.
            //
            // Leading (.navigation): back/forward arrows promoted from the
            // canvas headerBar per ADR-0072 §"Change 2" + ADR-0065 Amendment 1.
            // Removes 40 pt of vertical chrome from the canvas while keeping
            // the controls within thumb-reach of the trackpad gesture region.
            //
            // Trailing (.primaryAction): TopRightChrome (global namespace pill,
            // assistant, notifications, user menu) per ADR-0051 + ADR-0069.
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if let historyActor = deps.navigationHistoryActor {
                        NavigationHistoryToolbar(historyActor: historyActor)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    TopRightChrome(activeClusterId: activeClusterId)
                }
                // Inspector toggle (ADR-0073 §"Inspector visibility", ADR-0074 Change D).
                // Placed AFTER TopRightChrome so it lands at the far-trailing edge of the
                // toolbar — the canonical position per Apple HIG canonical productivity apps.
                // `sidebar.trailing` is the WWDC23 recommended symbol; foreground color
                // differentiates open/closed state to match the icon-only pattern from
                // Change A (no background fill, accentColor when active, secondary when closed).
                ToolbarItem(placement: .primaryAction) {
                    if let inspector = deps.inspectorViewModel {
                        Button {
                            inspector.toggle()
                        } label: {
                            Image(systemName: "sidebar.trailing")
                                .foregroundStyle(inspector.isVisible
                                    ? Color.accentColor
                                    : Color.secondary)
                        }
                        .help(inspector.isVisible ? "Hide Inspector (⌘⌥0)" : "Show Inspector (⌘⌥0)")
                        .accessibilityLabel(inspector.isVisible ? "Hide Inspector" : "Show Inspector")
                        .accessibilityIdentifier("AppShell.InspectorToggle")
                    }
                }
            }
        }
        .task { await trackActiveCluster() }
        // Cmd-Opt-0 shortcut routed via NotificationCenter so K8sManagerCommands
        // (which lives in the Commands graph, not the view tree) can fire it.
        .onReceive(
            NotificationCenter.default.publisher(for: .k8sManagerToggleInspector)
        ) { _ in
            deps.inspectorViewModel?.toggle()
        }
    }

    /// Subscribes to ``ClusterStripActor`` so the canvas header reacts to
    /// pin / activate / unpin without each child view re-implementing it.
    private func trackActiveCluster() async {
        @Dependency(\.clusterStrip) var stripActor
        for await snapshot in stripActor.stateStream() {
            if activeClusterId != snapshot.activeClusterId {
                activeClusterId = snapshot.activeClusterId
            }
        }
    }

    // MARK: - Sidebar column (Lens-style hierarchical resource tree)

    /// Hierarchical Kubernetes resource tree (ADR-0050 + ADR-0051).
    ///
    /// Replaces the flat `Feature`-based list. Legacy view models
    /// (HelmManagementViewModel, MetricsObservabilityViewModel, etc.) are
    /// preserved; they will be wired to specific `DocumentTab` cases in Onda 2.
    private var sidebarTree: some View {
        SidebarTreeView()
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
    }

    // MARK: - Canvas column (tab bar + active tab content + status bar)

    /// Canvas content — Band 2 of the ADR-0072 three-band ceiling.
    ///
    /// `.inspector(isPresented:)` is applied here per the WWDC23 "Inspectors in
    /// SwiftUI" pattern: the modifier is placed on the detail-column body, not
    /// on the `NavigationSplitView` itself. This produces the system-standard
    /// trailing slide animation on macOS 14+ (ADR-0073 §"NavigationSplitView
    /// extension to three columns").
    @ViewBuilder
    private var canvas: some View {
        VStack(spacing: 0) {
            SidebarCanvasView(
                openTabsActor: deps.openTabsActor,
                activeClusterId: activeClusterId
            )
            // Status footer (Band 3 — optional) per ADR-0072 §"Change 3".
            // Rendered only when an active cluster is selected so the footer
            // surfaces only when there is telemetry to report (cluster name,
            // server version, CPU/mem, watch + error counts). During the
            // cluster picker state the footer is absent — collapsing the shell
            // to two bands (toolbar + content) for a calmer initial canvas.
            if activeClusterId != nil {
                StatusBarView(toastViewModel: toastViewModel)
            }
        }
        .inspector(isPresented: inspectorBinding) {
            ResourceInspectorPanel(viewModel: deps.inspectorViewModel)
        }
    }

    /// Binding that bridges the optional `ResourceInspectorViewModel.isVisible`
    /// into the non-optional `Bool` required by `.inspector(isPresented:)`.
    ///
    /// When no inspector view model is wired (preview / menu bar scene) the
    /// binding is permanently `false` and the inspector column is hidden.
    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { deps.inspectorViewModel?.isVisible ?? false },
            set: { deps.inspectorViewModel?.isVisible = $0 }
        )
    }
}
