// AppShell.swift — NavigationSplitView shell
// Bounded context: app_shell (per ADR-0005)
// ADR ref: ADR-0022 (menu bar tray), ADR-0023 (command palette + shortcuts),
//          ADR-0032 (toasts), ADR-0050 (tab bar), ADR-0051 (Lens-style layout)
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
        openTabsActor: OpenTabsActor? = nil
    ) {
        let toastAggregate = ToastStackAggregate(
            initial: DomainToastStack(id: UUID().uuidString)
        )
        appShellDeps = AppShellDependencies(
            translationCatalog: BundleTranslationCatalog(bundle: .main),
            toastEmitter: ToastDomainEmitter(aggregate: toastAggregate),
            localePreference: InMemoryLocalePreferenceStore(),
            openTabsActor: openTabsActor,
            codeEditor: codeEditor
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

    public var body: some View {
        HStack(spacing: 0) {
            // Fixed-width cluster strip (ADR-0051). Always visible; not collapsible.
            ClusterStripView()

            // NavigationSplitView: hierarchical sidebar tree | canvas (ADR-0050/0051)
            NavigationSplitView {
                sidebarTree
            } detail: {
                canvas
            }
            .k8sKeyboardShortcuts(
                selectedFeature: $selectedFeature,
                paletteViewModel: paletteViewModel,
                toastViewModel: toastViewModel
            )
        }
        .task { await trackActiveCluster() }
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

    private var canvas: some View {
        VStack(spacing: 0) {
            SidebarCanvasView(
                openTabsActor: deps.openTabsActor,
                activeClusterId: activeClusterId
            )
            StatusBarView(toastViewModel: toastViewModel)
        }
    }
}
