// K8sManagerApp.swift — composition root.
// Wires concrete adapter implementations against domain ports via pointfreeco/swift-dependencies.
// ADR-0020: composition root is the only target that imports both domain cores AND adapters.
import SwiftUI
import AppShell
import Dependencies

// Domain core imports (read-models, ports — no infra)
import SharedKernel
import ClusterConnectivity
import ContextNavigation
import LLMProvider
import AssistantChat
import ClusterIntelligence
import LocalPersistence
import ResourceBrowser
import PortForwarding
import HelmManagement
import MetricsObservability
import TerminalSession

// Adapter imports (composition root is the ONLY place that imports infrastructure)
import SwiftkubeClientAdapter
import YamsKubeconfigAdapter
import KeychainAdapter
import GRDBPersistenceAdapter
import AnthropicAdapter
import OpenAIAdapter
import OpenAICompatibleAdapter
import MCPSwiftSDKAdapter
import AWSExecCredentialAdapter
import GCPExecCredentialAdapter
import AzureExecCredentialAdapter
import OIDCExecCredentialAdapter
import SubprocessExecCredentialAdapter
import PrometheusQueryAdapter
import WebSocketExecAdapter
import WebSocketPortForwardAdapter
import CodeEditorAdapter

@main
struct K8sManagerApp: App {
    init() {
        let loader = YamsKubeconfigLoader()
        let resolver = Self.buildResolver(using: loader)
        let kubernetesApi = SwiftkubeApiAdapter(resolver: resolver)

        // ADR-0025: per-cluster isolation — resolver is stateless; each call
        // produces a fresh ClusterParams from the on-disk kubeconfig.
        prepareDependencies {
            $0.kubeconfigLoader = loader
            $0.kubernetesApi = kubernetesApi
        }
    }

    var body: some Scene {
        K8sManagerRootScene()
    }
}

// MARK: - Composition helpers

private extension K8sManagerApp {

    /// Builds the `ClusterResolver` closure injected into `SwiftkubeApiAdapter`.
    ///
    /// The closure re-reads the default kubeconfig on every call. A cached read
    /// model (`ClusterRegistry`) will replace this in a subsequent round
    /// (ADR-0007 connection pool).
    nonisolated static func buildResolver(
        using loader: YamsKubeconfigLoader
    ) -> SwiftkubeApiAdapter.ClusterResolver {
        { clusterId in
            let config = try await loader.load(from: KubeconfigPath("~/.kube/config"))
            guard let context = config.contexts.first(where: { $0.cluster == clusterId.rawValue })
                ?? config.contexts.first(where: { $0.name == clusterId.rawValue }) else {
                throw KubernetesApiError.transportError(
                    detail: "ClusterId '\(clusterId.rawValue)' not found in kubeconfig"
                )
            }
            return try mapToClusterParams(context: context, in: config)
        }
    }

    /// Maps a resolved kubeconfig context to the `ClusterParams` required by
    /// `SwiftkubeApiAdapter`.
    ///
    /// Only bearer-token auth is supported in this slice; exec-plugin and
    /// client-certificate paths are deferred.
    nonisolated static func mapToClusterParams(
        context: KubeconfigContext,
        in config: Kubeconfig
    ) throws -> ClusterParams {
        guard let kubeconfigCluster = config.clusters.first(where: { $0.name == context.cluster }) else {
            throw KubernetesApiError.transportError(
                detail: "Cluster '\(context.cluster)' referenced by context '\(context.name)' not in kubeconfig"
            )
        }
        guard let kubeconfigUser = config.users.first(where: { $0.name == context.user }) else {
            throw KubernetesApiError.transportError(
                detail: "User '\(context.user)' referenced by context '\(context.name)' not in kubeconfig"
            )
        }
        guard let serverURL = URL(string: kubeconfigCluster.server) else {
            throw KubernetesApiError.transportError(
                detail: "Invalid server URL: '\(kubeconfigCluster.server)'"
            )
        }

        let auth = AuthInfo.bearerToken(
            BearerTokenAuth(token: kubeconfigUser.token ?? "")
        )
        let caStrategy = resolveCAStrategy(for: kubeconfigCluster)

        return ClusterParams(
            server: serverURL,
            auth: auth,
            insecureSkipTLSVerify: kubeconfigCluster.insecureSkipTLSVerify,
            caStrategy: caStrategy
        )
    }

    /// Derives the CA trust strategy from the raw cluster entry.
    ///
    /// Precedence: inline PEM data > path on disk > system trust store.
    nonisolated static func resolveCAStrategy(for cluster: KubeconfigCluster) -> CAStrategy {
        if let pemData = cluster.certificateAuthorityData {
            return .embedded(pemData: pemData)
        }
        if let path = cluster.certificateAuthorityPath {
            return .referenced(path: path)
        }
        return .system
    }
}
