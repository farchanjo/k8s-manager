// K8sManagerApp.swift — composition root.
// Wires concrete adapter implementations against domain ports via pointfreeco/swift-dependencies.
// Status: skeleton; adapter registrations pending real port implementations.
import SwiftUI
import AppShell

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
        // TODO: register concrete adapter implementations against @Dependency keys.
        // See ADR-0020 §"Decision outcome": composition root is the only target that
        // imports both domain cores AND adapters; business logic lives in domain cores,
        // not here.
    }

    var body: some Scene {
        K8sManagerRootScene()
    }
}
