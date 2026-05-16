// Views/ActiveTabContentView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (multi-document tab system, Onda 1 placeholder routing)

import SwiftUI
import SharedKernel

// MARK: - ActiveTabContentView

/// Canvas area below the tab bar that renders the content for the active `DocumentTab`.
///
/// **Onda 1 scope**: wires `ClusterListView` to `.overview` and `ResourceBrowserView`
/// to `.resourceList(kind: .pods)` as starting points. All other tab kinds display
/// a placeholder view indicating the feature will arrive in Onda 2.
///
/// When `activeTab` is `nil` (no tab open yet), an `ContentUnavailableView` is shown.
public struct ActiveTabContentView: View {

    /// The currently active tab, or `nil` when the tab bar is empty.
    let activeTab: DocumentTab?

    public init(activeTab: DocumentTab?) {
        self.activeTab = activeTab
    }

    public var body: some View {
        Group {
            if let tab = activeTab {
                tabContent(for: tab)
            } else {
                noTabState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Private routing

    @ViewBuilder
    private func tabContent(for tab: DocumentTab) -> some View {
        switch tab {
        case .overview:
            ClusterListView()

        case .resourceList(_, let kind, _) where kind.kind == "Pod":
            ResourceBrowserView()

        case .applications:
            placeholderView(title: "Applications", icon: "app.gift")

        case .nodes:
            placeholderView(title: "Nodes", icon: "server.rack")

        case .resourceList(_, let kind, _):
            placeholderView(title: kind.kind, icon: "list.bullet")

        case .resourceDetail:
            placeholderView(title: "Resource Detail", icon: "doc.text")

        case .yamlEditor:
            placeholderView(title: "YAML Editor", icon: "pencil.and.outline")

        case .logs:
            placeholderView(title: "Logs", icon: "text.alignleft")

        case .exec:
            placeholderView(title: "Terminal", icon: "terminal")

        case .events:
            placeholderView(title: "Events", icon: "calendar.badge.clock")

        case .helmRelease:
            placeholderView(title: "Helm Release", icon: "shippingbox")

        case .namespaces:
            placeholderView(title: "Namespaces", icon: "folder")

        case .portForward:
            placeholderView(title: "Port Forward", icon: "arrow.left.arrow.right")

        case .customResource:
            placeholderView(title: "Custom Resource", icon: "puzzlepiece.extension")

        case .securityOverview:
            placeholderView(title: "Security Center", icon: "lock.shield")

        case .apiResources:
            placeholderView(title: "API Resources", icon: "list.bullet.rectangle.portrait")
        }
    }

    private var noTabState: some View {
        ContentUnavailableView(
            "No tab open",
            systemImage: "sidebar.right",
            description: Text("Select a resource from the sidebar to open a tab.")
        )
    }

    private func placeholderView(title: String, icon: String) -> some View {
        ContentUnavailableView(
            "\(title) — coming in Onda 2",
            systemImage: icon,
            description: Text("This view will be implemented in the next delivery wave.")
        )
    }
}
