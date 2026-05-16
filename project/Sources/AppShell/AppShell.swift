// AppShell.swift — NavigationSplitView shell
// Bounded context: app_shell (per ADR-0005)
// ADR ref: ADR-0022 (menu bar tray), ADR-0023 (command palette + shortcuts), ADR-0032 (toasts)
import Foundation
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

    public init() {
        let toastAggregate = ToastStackAggregate(
            initial: DomainToastStack(id: UUID().uuidString)
        )
        appShellDeps = AppShellDependencies(
            translationCatalog: BundleTranslationCatalog(bundle: .main),
            toastEmitter: ToastDomainEmitter(aggregate: toastAggregate),
            localePreference: InMemoryLocalePreferenceStore()
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

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .k8sKeyboardShortcuts(
            selectedFeature: $selectedFeature,
            paletteViewModel: paletteViewModel,
            toastViewModel: toastViewModel
        )
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(Feature.allCases, selection: $selectedFeature) { feature in
            NavigationLink(value: feature) {
                Label(feature.title, systemImage: feature.systemImage)
            }
        }
        .navigationTitle("K8sManager")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedFeature {
        case .clusters:      ClusterListView()
        case .contexts:      ContextNavigationView()
        case .resources:     ResourceBrowserView()
        case .chat:          AssistantChatView()
        case .intelligence:  ClusterIntelligenceView()
        case .providers:     LLMProviderView()
        case .persistence:   LocalPersistenceView()
        case .helm:          HelmManagementView()
        case .metrics:       MetricsObservabilityView()
        case .portForward:   PortForwardingView()
        case .terminal:      TerminalSessionView()
        case .none:          emptyState
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Select a feature",
            systemImage: "sidebar.left",
            description: Text("Pick from the sidebar")
        )
    }
}
