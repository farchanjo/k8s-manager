// K8sManagerApp.swift — composition root.
// Wires concrete adapter implementations against domain ports via pointfreeco/swift-dependencies.
// ADR-0020: composition root is the only target that imports both domain cores AND adapters.
import AppKit
import AsyncHTTPClient
import GRDB
import Logging
import SwiftUI

import AppShell
import Dependencies

// Domain core imports (read-models, ports — no infra)
import AssistantChat
import ClusterConnectivity
import ClusterIntelligence
import ContextNavigation
import HelmManagement
import LocalPersistence
import LLMProvider
import MetricsObservability
import PortForwarding
import ResourceBrowser
import SharedKernel
import TerminalSession

// Adapter imports (composition root is the ONLY place that imports infrastructure)
import KubeconfigContextNavigationAdapter
import AnthropicAdapter
import AWSExecCredentialAdapter
import AzureExecCredentialAdapter
import CodeEditorAdapter
import GCPExecCredentialAdapter
import GRDBPersistenceAdapter
import KeychainAdapter
import MCPSwiftSDKAdapter
import OIDCExecCredentialAdapter
import OpenAIAdapter
import OpenAICompatibleAdapter
import PrometheusQueryAdapter
import SubprocessExecCredentialAdapter
import SwiftkubeClientAdapter
import WebSocketExecAdapter
import WebSocketPortForwardAdapter
import YamsKubeconfigAdapter

// MARK: - Entry point

@main
struct K8sManagerApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self)
    private var appDelegate

    init() {
        do {
            try Self.wireSync()
        } catch {
            let log = Logger(label: "K8sManagerApp.bootstrap")
            log.critical("Composition-root bootstrap failed: \(error)")
            fatalError("Bootstrap failed: \(error)")
        }
        Self.wireAsync()
    }

    var body: some Scene {
        K8sManagerRootScene()
    }
}

// MARK: - Sync bootstrap

private extension K8sManagerApp {

    /// Wires all synchronously constructible adapters and registers their ports.
    nonisolated static func wireSync() throws {
        let keychain = KeychainAccessAdapter()
        let keyManager = AuditChainKeyManager(keychainAdapter: keychain)
        let db = try openDatabase()
        let (chatRepo, providerRepo, clusterStore, auditChain) = wirePersistence(
            db: db, keyManager: keyManager
        )
        let (loader, kubeApi, resourceList) = wireKubernetes()
        let contextRepo = KubeconfigContextRepository(loader: loader, metadataStore: clusterStore)
        let activeContextWatch = KubeconfigActiveContextWatch(repository: contextRepo, loader: loader)
        let sidebarReadModel = KubeconfigSidebarReadModel(repository: contextRepo, watch: activeContextWatch)

        prepareDependencies { values in
            // Connectivity
            values.kubeconfigLoader = loader
            values.kubernetesApi = kubeApi
            values.kubernetesResourceList = resourceList

            // Persistence
            values.chatRepository = chatRepo
            values.providerRepository = providerRepo
            values.clusterMetadataStore = clusterStore
            values.auditChain = auditChain

            // ContextNavigation ports
            values.contextRepository = contextRepo
            values.activeContextWatch = activeContextWatch
            values.sidebarReadModel = sidebarReadModel

            // Keychain
            values.keychainAccess = keychain

            // Metrics — PrometheusEndpoint is passed per-query; singleton client here
            values.prometheusQuery = PrometheusHTTPClient(httpClient: .shared)

            // Port-forward — placeholder URL; real URL is resolved per-session
            // by the connection lifecycle manager (subsequent round, ADR-0007).
            let placeholderURL = URL(string: "https://kubernetes.default.svc")!
            values.portForwardChannel = WebSocketPortForwardAdapter(
                urlSession: .shared,
                baseURL: placeholderURL
            )
        }
    }

    /// Opens the application SQLite database at the default Application Support path.
    nonisolated static func openDatabase() throws -> DatabaseQueue {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.path
        return try SchemaMigrator.makeQueue(
            at: base + "/K8sManager/storage.sqlite3",
            logger: Logger(label: "SchemaMigrator")
        )
    }

    /// Constructs the four GRDB repository adapters sharing one `DatabaseQueue`.
    nonisolated static func wirePersistence(
        db: any DatabaseWriter,
        keyManager: AuditChainKeyManager
    ) -> (GRDBChatRepository, GRDBProviderRepository, GRDBClusterMetadataStore, GRDBAuditChainStore) {
        let chatRepo = GRDBChatRepository(db: db)
        let providerRepo = GRDBProviderRepository(db: db)
        let clusterStore = GRDBClusterMetadataStore(db: db)
        let auditChain = GRDBAuditChainStore(
            db: db,
            keyProvider: makeSyncKeyProvider(keyManager)
        )
        return (chatRepo, providerRepo, clusterStore, auditChain)
    }

    /// Wraps async `AuditChainKeyManager.currentKey()` in the synchronous
    /// `KeyProvider` closure expected by `GRDBAuditChainStore`.
    ///
    /// Blocks via `DispatchSemaphore`. Only called from GRDB write worker threads.
    nonisolated static func makeSyncKeyProvider(
        _ manager: AuditChainKeyManager
    ) -> @Sendable () throws -> Data? {
        { [manager] in
            let semaphore = DispatchSemaphore(value: 0)
            let box = _SyncBox<Data>()
            Task.detached {
                do { box.set(.success(try await manager.currentKey())) }
                catch { box.set(.failure(error)) }
                semaphore.signal()
            }
            semaphore.wait()
            return try box.get()
        }
    }

    /// Builds the kubeconfig loader, API adapter, and resource-list adapter.
    nonisolated static func wireKubernetes() -> (
        YamsKubeconfigLoader, SwiftkubeApiAdapter, SwiftkubeResourceListAdapter
    ) {
        let loader = YamsKubeconfigLoader()
        let resolver = buildResolver(using: loader)
        return (loader, SwiftkubeApiAdapter(resolver: resolver), SwiftkubeResourceListAdapter(resolver: resolver))
    }
}

// MARK: - Async bootstrap

private extension K8sManagerApp {

    /// Wires adapters requiring async construction.
    ///
    /// Registers: `MCPInProcessTransport`, LLM adapter (when Anthropic key present).
    nonisolated static func wireAsync() {
        Task.detached(priority: .userInitiated) {
            await wireMCP()
            await wireLLMIfKeyPresent()
        }
    }

    /// Constructs `MCPInProcessTransport` and registers it as `\.mcpTransport`.
    nonisolated static func wireMCP() async {
        @Dependency(\.kubernetesResourceList) var resourceList
        do {
            let transport = try await MCPInProcessTransport(resourceListPort: resourceList)
            prepareDependencies { $0.mcpTransport = transport }
        } catch {
            let log = Logger(label: "K8sManagerApp.mcp")
            log.error("MCPInProcessTransport init failed: \(error)")
        }
    }

    /// Reads an Anthropic API key from Keychain and registers
    /// `AnthropicStreamingAdapter` as `\.llmStreaming` when found.
    nonisolated static func wireLLMIfKeyPresent() async {
        @Dependency(\.keychainAccess) var keychain
        let entry = KeychainEntry(
            namespace: .llm,
            account: "anthropic-default",
            label: "Anthropic API Key"
        )
        guard
            let keyData = try? await keychain.readSecret(for: entry),
            let apiKey = String(data: keyData, encoding: .utf8),
            !apiKey.isEmpty
        else { return }
        let adapter = AnthropicStreamingAdapter(apiKey: apiKey, model: "claude-sonnet-4-6")
        prepareDependencies { $0.llmStreaming = adapter }
    }
}

// MARK: - Cluster resolver helpers

private extension K8sManagerApp {

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
        let auth = AuthInfo.bearerToken(BearerTokenAuth(token: kubeconfigUser.token ?? ""))
        return ClusterParams(
            server: serverURL,
            auth: auth,
            insecureSkipTLSVerify: kubeconfigCluster.insecureSkipTLSVerify,
            caStrategy: resolveCAStrategy(for: kubeconfigCluster)
        )
    }

    nonisolated static func resolveCAStrategy(for cluster: KubeconfigCluster) -> CAStrategy {
        if let pemData = cluster.certificateAuthorityData { return .embedded(pemData: pemData) }
        if let path = cluster.certificateAuthorityPath { return .referenced(path: path) }
        return .system
    }
}

// MARK: - Thread-safe single-write result box

/// Bridges async results across a semaphore wait.
///
/// `@unchecked Sendable` is justified: `NSLock` serialises all mutations.
private final class _SyncBox<T: Sendable>: @unchecked Sendable {
    private var result: Result<T, Error>?
    private let lock = NSLock()

    func set(_ result: Result<T, Error>) { lock.withLock { self.result = result } }

    func get() throws -> T? {
        switch lock.withLock({ result }) {
        case .success(let v): return v
        case .failure(let e): throw e
        case .none: return nil
        }
    }
}

// MARK: - App activation delegate

/// Promotes a `swift run` invocation (no bundle, no Info.plist) into a
/// regular foreground macOS app.
final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
