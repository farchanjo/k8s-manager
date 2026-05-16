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
            // ADR-0042: enforce single-instance before any other bootstrap work.
            let lockPath = Self.defaultLockPath()
            try SingleInstanceLock.acquireOrExit(lockPath: lockPath)
        } catch SingleInstanceError.alreadyRunning(let existingPid) {
            let log = Logger(label: "K8sManagerApp.singleInstance")
            log.warning("Another instance is already running (pid=\(existingPid.map(String.init) ?? "unknown")). Activating it.")
            Self.activateExistingInstance(pid: existingPid)
            // activateExistingInstance calls NSApp.terminate; this path should
            // not be reached, but guard against a no-op delegate scenario.
            return
        } catch {
            let log = Logger(label: "K8sManagerApp.singleInstance")
            log.error("Single-instance lock error: \(error). Proceeding without enforcement.")
        }

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

// MARK: - Single-instance helpers

private extension K8sManagerApp {

    /// Returns the canonical lock file path via ``ApplicationPaths`` (ADR-0026, ADR-0042).
    nonisolated static func defaultLockPath() -> String {
        ApplicationPaths.instanceLockURL.path
    }

    /// Attempts to bring the existing instance to the foreground, then exits.
    nonisolated static func activateExistingInstance(pid: pid_t?) {
        if let pid, let existing = NSRunningApplication(processIdentifier: pid) {
            existing.activate(options: [.activateAllWindows])
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}

// MARK: - Sync bootstrap

private extension K8sManagerApp {

    /// Wires all synchronously constructible adapters and registers their ports.
    nonisolated static func wireSync() throws {
        let keychain = KeychainAccessAdapter()
        let keyManager = AuditChainKeyManager(keychainAdapter: keychain)
        let db = try openDatabase()
        let (chatRepo, providerRepo, clusterStore, auditChain, terminalRepo, persistenceActor) = wirePersistence(
            db: db, keyManager: keyManager
        )
        let (loader, kubeApi, resourceList, discoveryAdapter) = wireKubernetes()
        let contextRepo = KubeconfigContextRepository(loader: loader, metadataStore: clusterStore)
        let activeContextWatch = KubeconfigActiveContextWatch(repository: contextRepo, loader: loader)
        let sidebarReadModel = KubeconfigSidebarReadModel(repository: contextRepo, watch: activeContextWatch)
        let domainEventBus = DomainEventBus()

        prepareDependencies { values in
            // Domain event bus (ADR-0040)
            values.domainEventBus = domainEventBus

            // Connectivity
            values.kubeconfigLoader = loader
            values.kubernetesApi = kubeApi
            values.kubernetesResourceList = resourceList

            // Metrics — discovery adapter resolves Prometheus endpoints via k8s Services
            values.endpointDiscovery = discoveryAdapter

            // Persistence — single write gate (ADR-0010)
            values.persistenceActor = persistenceActor
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

            // Metrics — PrometheusEndpoint is passed per-query; singleton client here.
            // SharedNetworking.httpClient is the shared pool (ADR-0007).
            values.prometheusQuery = PrometheusHTTPClient(httpClient: SharedNetworking.httpClient)

            // Port-forward and pod exec — placeholder base URL; resolved per-session
            // by the connection lifecycle manager (ADR-0007 / ADR-0017).
            let placeholderURL = URL(string: "https://kubernetes.default.svc")!
            values.portForwardChannel = WebSocketPortForwardAdapter(
                urlSession: .shared,
                baseURL: placeholderURL
            )
            values.podExec = WebSocketExecAdapter(
                urlSession: .shared,
                apiServerBase: placeholderURL
            )

            // TerminalSession repository (GRDB-backed; ADR-0017)
            values.terminalRepository = terminalRepo

            // HelmManagement extras — unimplemented sentinels until adapters land
            wireHelmManagementExtras(into: &values)

            // PortForwarding extras — unimplemented sentinels until adapters land
            wirePortForwardingExtras(into: &values)

            // LocalPersistence + MetricsObservability extras
            wirePersistenceExtras(into: &values)
        }
    }

    /// Registers HelmManagement ports that have no live adapter yet.
    ///
    /// - `releaseDecoder`: gzip+protobuf Helm secret decoder — adapter deferred.
    /// - `auditLog`: Helm rollback audit log — GRDB adapter deferred.
    nonisolated static func wireHelmManagementExtras(into values: inout DependencyValues) {
        values.releaseDecoder = UnimplementedReleaseDecoderPort()
        values.auditLog = UnimplementedAuditLogPort()
    }

    /// Registers PortForwarding ports that have no live adapter yet.
    ///
    /// - `serviceEndpointReader`: EndpointSlice query adapter — deferred.
    /// - `portForwardRepository`: GRDB session store — deferred (ADR-0007).
    nonisolated static func wirePortForwardingExtras(into values: inout DependencyValues) {
        values.serviceEndpointReader = UnimplementedServiceEndpointReaderPort()
        values.portForwardRepository = UnimplementedPortForwardRepositoryPort()
    }

    /// Registers LocalPersistence and MetricsObservability ports without live adapters.
    ///
    /// - `operatorPreferences`: UX preference store — GRDB adapter deferred.
    /// - `prometheusEndpointRepository`: Endpoint config store — adapter deferred.
    nonisolated static func wirePersistenceExtras(into values: inout DependencyValues) {
        values.operatorPreferences = UnimplementedOperatorPreferencesPort()
        values.prometheusEndpointRepository = UnimplementedPrometheusEndpointRepositoryPort()
    }

    /// Opens the application SQLite database via ``ApplicationPaths`` (ADR-0026).
    nonisolated static func openDatabase() throws -> DatabaseQueue {
        try ApplicationPaths.ensureSupportDirectoryExists()
        return try SchemaMigrator.makeQueue(
            at: ApplicationPaths.storageURL.path,
            logger: Logger(label: "SchemaMigrator")
        )
    }

    /// Constructs the four GRDB repository adapters and the `PersistenceActor`
    /// sharing one `DatabaseWriter`.
    ///
    /// The returned `PersistenceActor` wraps the same writer via
    /// `GRDBWriterAdapter` and must be registered in `prepareDependencies`
    /// as `values.persistenceActor` (ADR-0010).
    nonisolated static func wirePersistence(
        db: any DatabaseWriter,
        keyManager: AuditChainKeyManager
    ) -> (GRDBChatRepository, GRDBProviderRepository, GRDBClusterMetadataStore, GRDBAuditChainStore, GRDBTerminalRepository, PersistenceActor) {
        let chatRepo = GRDBChatRepository(db: db)
        let providerRepo = GRDBProviderRepository(db: db)
        let clusterStore = GRDBClusterMetadataStore(db: db)
        let auditChain = GRDBAuditChainStore(
            db: db,
            keyProvider: makeSyncKeyProvider(keyManager)
        )
        let terminalRepo = GRDBTerminalRepository(db: db)
        let persistenceActor = PersistenceActor(writer: GRDBWriterAdapter(writer: db))
        return (chatRepo, providerRepo, clusterStore, auditChain, terminalRepo, persistenceActor)
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

    /// Builds the kubeconfig loader, API adapter, resource-list adapter, and
    /// Prometheus discovery adapter.
    nonisolated static func wireKubernetes() -> (
        YamsKubeconfigLoader,
        SwiftkubeApiAdapter,
        SwiftkubeResourceListAdapter,
        SwiftkubePrometheusDiscoveryAdapter
    ) {
        let loader = YamsKubeconfigLoader()
        let resolver = buildResolver(using: loader)
        // Discovery adapter uses a UUID-keyed resolver. The UUID corresponds
        // to PrometheusEndpoint.kubernetesContextId, which originates from
        // the cluster context import and is stored as a stable UUIDv7.
        let discoveryResolver: SwiftkubePrometheusDiscoveryAdapter.ClusterResolver = {
            uuid in try await resolver(ClusterId(uuid.uuidString))
        }
        return (
            loader,
            SwiftkubeApiAdapter(resolver: resolver),
            SwiftkubeResourceListAdapter(resolver: resolver),
            SwiftkubePrometheusDiscoveryAdapter(resolver: discoveryResolver)
        )
    }
}

// MARK: - Async bootstrap

private extension K8sManagerApp {

    /// Wires adapters requiring async construction.
    ///
    /// Registers: `MCPInProcessTransport`, `LLMProviderRouter`, and the
    /// `WatchStreamCoordinator` singleton.
    nonisolated static func wireAsync() {
        Task.detached(priority: .userInitiated) {
            await wireMCP()
            await wireLLM()
            await wireWatchCoordinator()
        }
    }

    /// Constructs `WatchStreamCoordinator` and registers it as `\.watchStreamCoordinator`.
    ///
    /// The coordinator singleton is registered here so the whole process shares
    /// one instance. `OpenTabsActor` integration is wired separately at cluster
    /// session creation time via `OpenTabsActor.registerWatcher(for:task:)` and
    /// `stateStream()` subscription.
    nonisolated static func wireWatchCoordinator() async {
        let coordinator = WatchStreamCoordinator()
        prepareDependencies { $0.watchStreamCoordinator = coordinator }
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

    /// Builds the factory map and registers `LLMProviderRouter` as `\.llmStreaming`.
    ///
    /// Each factory reads the API key from Keychain using the profile's `keyAlias`
    /// and constructs the matching streaming adapter.
    nonisolated static func wireLLM() async {
        @Dependency(\.keychainAccess) var keychain
        @Dependency(\.llmProviderRegistry) var registry

        let factories: [LLMProvider.ProviderKind: @Sendable (LLMProvider.ProviderProfile) async throws -> any LLMStreamingPort] = [
            .anthropic: { profile in
                let key = try await Self.readKey(alias: profile.keyAlias, keychain: keychain)
                return AnthropicStreamingAdapter(apiKey: key, model: profile.modelId)
            },
            .openai: { profile in
                let key = try await Self.readKey(alias: profile.keyAlias, keychain: keychain)
                return OpenAIStreamingAdapter(apiKey: key, model: profile.modelId)
            },
            .openaiCompatible: { profile in
                let key = try? await Self.readKey(alias: profile.keyAlias, keychain: keychain)
                return try OpenAICompatibleStreamingAdapter(
                    apiKey: key,
                    host: profile.baseURL?.host ?? "localhost",
                    port: profile.baseURL?.port,
                    scheme: profile.baseURL?.scheme ?? "http",
                    model: profile.modelId
                )
            },
        ]

        let router = LLMProviderRouter(registry: registry, factories: factories)
        prepareDependencies { $0.llmStreaming = router }
    }

    /// Reads a Keychain secret by alias and returns it as a UTF-8 string.
    ///
    /// - Throws: `LLMStreamingError.keyNotFound` when the entry is absent or unreadable.
    nonisolated static func readKey(
        alias: String,
        keychain: any KeychainAccessPort
    ) async throws -> String {
        let entry = KeychainEntry(
            namespace: .llm,
            account: alias,
            label: "\(alias) API Key"
        )
        let data = try await keychain.readSecret(for: entry)
        guard let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw LLMStreamingError.keyNotFound(alias: alias)
        }
        return key
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
/// regular foreground macOS app and handles graceful shutdown.
final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Shuts down the shared networking stack (ADR-0007) before the process exits.
    ///
    /// `applicationWillTerminate` is called synchronously on the main thread.
    /// A detached `Task` drives the async shutdown; the semaphore ensures the
    /// NIO threads are drained before `applicationWillTerminate` returns.
    func applicationWillTerminate(_ notification: Notification) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            try? await SharedNetworking.shutdown()
            semaphore.signal()
        }
        semaphore.wait()
    }
}
