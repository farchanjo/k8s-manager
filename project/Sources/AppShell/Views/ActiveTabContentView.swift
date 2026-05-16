// Views/ActiveTabContentView.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0050 (multi-document tab system), ADR-0015 (Helm native phased)
// ADR ref: ADR-0021 (detail drawer — inspector wiring, Onda 2)

import SwiftUI
import ResourceBrowser
import SharedKernel

// MARK: - ActiveTabContentView

/// Canvas area below the tab bar that renders the content for the active `DocumentTab`.
///
/// **Onda 2**: wires all 9 Workload kinds (Pods, Deployments, DaemonSets, StatefulSets,
/// ReplicaSets, ReplicationControllers, Jobs, CronJobs) plus the Workloads Overview
/// dashboard. `SecurityOverviewView` and `CustomResourceListView` carried forward
/// from earlier work.
///
/// When `activeTab` is `nil` (no tab open yet), a `ContentUnavailableView` is shown.
public struct ActiveTabContentView: View {

    /// The currently active tab, or `nil` when the tab bar is empty.
    let activeTab: DocumentTab?

    /// Open-tab callback forwarded into the drawer for action buttons.
    let onOpenTab: (DocumentTab) -> Void

    /// The resource ref selected in any list view — drives the inspector drawer.
    @State private var selectedRef: ResourceRef?

    public init(
        activeTab: DocumentTab?,
        onOpenTab: @escaping (DocumentTab) -> Void = { _ in }
    ) {
        self.activeTab = activeTab
        self.onOpenTab = onOpenTab
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
        .inspector(isPresented: Binding(
            get: { self.selectedRef != nil },
            set: { presented in if !presented { self.selectedRef = nil } }
        )) {
            if let ref = self.selectedRef, let tab = self.activeTab {
                ResourceDetailDrawer(
                    clusterId: tab.clusterId,
                    ref: ref,
                    onOpenTab: self.onOpenTab,
                    onDismiss: { self.selectedRef = nil }
                )
                .inspectorColumnWidth(min: 360, ideal: 480, max: 600)
            }
        }
    }

    // MARK: Private routing

    @ViewBuilder
    private func tabContent(for tab: DocumentTab) -> some View {
        switch tab {
        case .overview:
            ClusterListView()

        case .applications(let clusterId):
            WorkloadsOverviewView(clusterId: clusterId)

        case .nodes(let clusterId):
            NodesListView(clusterId: clusterId)

        case .resourceList(let clusterId, let kind, let namespace):
            workloadListView(clusterId: clusterId, kind: kind, namespace: namespace)

        case .resourceDetail:
            placeholderView(title: "Resource Detail", icon: "doc.text")

        case .yamlEditor:
            placeholderView(title: "YAML Editor", icon: "pencil.and.outline")

        case .logs:
            placeholderView(title: "Logs", icon: "text.alignleft")

        case .exec:
            placeholderView(title: "Terminal", icon: "terminal")

        case .events(let clusterId, let scope):
            EventsListView(
                clusterId: clusterId,
                namespace: scope.flatMap {
                    if case .namespace(let ns) = $0 { return ns }
                    return nil
                }
            )

        case .helmRelease(let clusterId, let releaseName, let namespace):
            HelmReleaseDetailView(
                clusterId: clusterId,
                releaseName: releaseName,
                namespace: namespace
            )

        case .namespaces(let clusterId):
            NamespacesListView(clusterId: clusterId)

        case .portForward:
            placeholderView(title: "Port Forward", icon: "arrow.left.arrow.right")

        case .customResource(let clusterId, let gvr):
            CustomResourceListView(clusterId: clusterId, gvr: gvr)

        case .securityOverview(let clusterId):
            SecurityOverviewView(clusterId: clusterId)

        case .apiResources(let clusterId):
            APIResourcesListView(clusterId: clusterId)

        case .applyYAML(let clusterId):
            ApplyYAMLView(clusterId: clusterId)

        case .diagnostics(let clusterId):
            DiagnosticsView(clusterId: clusterId)
        }
    }

    private var noTabState: some View {
        ContentUnavailableView(
            "No tab open",
            systemImage: "sidebar.right",
            description: Text("Select a resource from the sidebar to open a tab.")
        )
    }

    // MARK: - Workload kind routing (Onda 2)

    /// Routes `.resourceList` tabs to the appropriate kind-specific list view.
    ///
    /// All 9 workload kinds are handled by dedicated views. Other kinds fall
    /// through to a placeholder until Onda 3 delivers their views.
    @ViewBuilder
    private func workloadListView(
        clusterId: ClusterId,
        kind: ResourceKind,
        namespace: String?
    ) -> some View {
        switch kind.kind {

        // MARK: Helm releases list (helm.sh/v3/HelmRelease)
        case "HelmRelease":
            HelmReleasesListView(clusterId: clusterId)

        case "Pod":
            PodsListView(clusterId: clusterId, namespace: namespace)
        case "Deployment":
            DeploymentsListView(clusterId: clusterId, namespace: namespace)
        case "DaemonSet":
            DaemonSetsListView(clusterId: clusterId, namespace: namespace)
        case "StatefulSet":
            StatefulSetsListView(clusterId: clusterId, namespace: namespace)
        case "ReplicaSet":
            ReplicaSetsListView(clusterId: clusterId, namespace: namespace)
        case "ReplicationController":
            ReplicationControllersListView(clusterId: clusterId, namespace: namespace)
        case "Job":
            JobsListView(clusterId: clusterId, namespace: namespace)
        case "CronJob":
            CronJobsListView(clusterId: clusterId, namespace: namespace)

        // MARK: Config category (Onda 2)
        case "ConfigMap":
            ConfigMapsListView(clusterId: clusterId)
        case "Secret":
            SecretsListView(clusterId: clusterId)
        case "ResourceQuota":
            ResourceQuotasListView(clusterId: clusterId)
        case "LimitRange":
            LimitRangesListView(clusterId: clusterId)
        case "HorizontalPodAutoscaler":
            HPAListView(clusterId: clusterId)
        case "PodDisruptionBudget":
            PodDisruptionBudgetsListView(clusterId: clusterId)
        case "PriorityClass":
            PriorityClassesListView(clusterId: clusterId)
        case "RuntimeClass":
            RuntimeClassesListView(clusterId: clusterId)
        case "Lease":
            LeasesListView(clusterId: clusterId)
        case "MutatingWebhookConfiguration":
            MutatingWebhooksListView(clusterId: clusterId)
        case "ValidatingWebhookConfiguration":
            ValidatingWebhooksListView(clusterId: clusterId)

        // MARK: Network category (Onda 2)
        case "Service":
            ServicesListView(clusterId: clusterId)
        case "Endpoints":
            EndpointsListView(clusterId: clusterId)
        case "EndpointSlice":
            EndpointSlicesListView(clusterId: clusterId)
        case "Ingress":
            IngressesListView(clusterId: clusterId)
        case "IngressClass":
            IngressClassesListView(clusterId: clusterId)
        case "NetworkPolicy":
            NetworkPoliciesListView(clusterId: clusterId)

        // MARK: Storage category (Onda 2)
        case "PersistentVolumeClaim":
            PVCsListView(clusterId: clusterId)
        case "PersistentVolume":
            PVsListView(clusterId: clusterId)
        case "StorageClass":
            StorageClassesListView(clusterId: clusterId)
        case "VolumeSnapshot":
            VolumeSnapshotsListView(clusterId: clusterId)
        case "VolumeSnapshotClass":
            VolumeSnapshotClassesListView(clusterId: clusterId)
        case "CSIDriver":
            CSIDriversListView(clusterId: clusterId)

        // MARK: RBAC category (Onda 2)
        case "ServiceAccount":
            ServiceAccountsListView(clusterId: clusterId)
        case "ClusterRole":
            ClusterRolesListView(clusterId: clusterId)
        case "Role":
            RolesListView(clusterId: clusterId)
        case "ClusterRoleBinding":
            ClusterRoleBindingsListView(clusterId: clusterId)
        case "RoleBinding":
            RoleBindingsListView(clusterId: clusterId)
        case "CertificateSigningRequest":
            CertificateSigningRequestsListView(clusterId: clusterId)

        default:
            placeholderView(title: kind.kind, icon: "list.bullet")
        }
    }

    private func placeholderView(title: String, icon: String) -> some View {
        ContentUnavailableView(
            "\(title) — coming in Onda 3",
            systemImage: icon,
            description: Text("This view will be implemented in a future delivery wave.")
        )
    }
}
