// AppShell.swift — NavigationSplitView shell
// Bounded context: app_shell (per ADR-0005)
import SwiftUI

/// Namespace marker for the AppShell bounded context.
///
/// Domain types, ports, and actors land under this enum in subsequent rounds.
/// This file exists so the target compiles cleanly under Swift 6 strict concurrency.
public enum AppShell: Sendable {
    /// Build identifier — bumped manually until CI emits this.
    public static let moduleVersion = "0.0.1-skeleton"
}

/// Root SwiftUI scene presenting a `NavigationSplitView` shell.
///
/// Wired by the `K8sManagerApp` composition root. All feature panels
/// are driven by `Feature.allCases` through the sidebar selection binding.
public struct K8sManagerRootScene: Scene {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            AppShellView()
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentSize)
    }
}

/// Top-level shell view — sidebar + detail layout.
///
/// `selectedFeature` defaults to `.clusters` so the app opens to a
/// useful state without requiring an explicit sidebar tap.
public struct AppShellView: View {
    @State private var selectedFeature: Feature? = .clusters

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    private var sidebar: some View {
        List(Feature.allCases, selection: $selectedFeature) { feature in
            NavigationLink(value: feature) {
                Label(feature.title, systemImage: feature.systemImage)
            }
        }
        .navigationTitle("K8sManager")
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    }

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
