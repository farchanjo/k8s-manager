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

// MARK: - BootstrapError

/// Unrecoverable errors detected during app bootstrap (ADR-0042).
enum BootstrapError: Error, Sendable {
    /// The application's storage directory resides on a network volume.
    ///
    /// SQLite WAL locking is unreliable on network filesystems (NFS, SMB, AFP,
    /// WebDAV). The app must refuse to open the database on such volumes and
    /// prompt the operator to choose a local path (ADR-0042 §Network-volume rejection).
    case nonLocalStorageVolume(path: String)
}

// MARK: - Entry point

@main
struct K8sManagerApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self)
    private var appDelegate

    /// Shared `OpenTabsActor` owned by the composition root.
    ///
    /// One actor backs both the `OpenTabsPort` consumed by view models (via
    /// `swift-dependencies`) AND the SwiftUI tab-bar canvas (via
    /// `AppShellDependencies.openTabsActor`). Wiring both pathways from a
    /// single instance prevents the sidebar/tab-bar drift bug.
    ///
    /// Persistence path lives under `~/Library/Application Support/K8sManager/workspace/`
    /// for now; ADR-0050 multi-cluster scoping (per-cluster `open-tabs.json`)
    /// is deferred until the cluster-strip selects which subdirectory to load.
    private let openTabsActor: OpenTabsActor

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
            // Initialise stored properties so the App struct stays valid.
            self.openTabsActor = OpenTabsActor(persistenceURL: Self.openTabsPersistenceURL)
            return
        } catch {
            let log = Logger(label: "K8sManagerApp.singleInstance")
            log.error("Single-instance lock error: \(error). Proceeding without enforcement.")
        }

        // ADR-0042 §Network-volume rejection: probe storage directory filesystem
        // type before opening any SQLite connection. A non-local volume (NFS, SMB,
        // AFP, WebDAV) causes unreliable POSIX advisory locks and silent WAL
        // corruption. Surface a blocking alert and exit rather than opening the DB.
        do {
            let isLocal = try ApplicationPaths.isLocalVolume(at: ApplicationPaths.storageURL)
            if !isLocal {
                Self.rejectNonLocalVolume(path: ApplicationPaths.storageURL.path)
                self.openTabsActor = OpenTabsActor(persistenceURL: Self.openTabsPersistenceURL)
                return
            }
        } catch {
            // If the probe itself fails the volume is inaccessible; treat conservatively.
            let log = Logger(label: "K8sManagerApp.volumeCheck")
            log.warning("Volume locality probe failed: \(error). Proceeding with caution.")
        }

        let openTabsActor = OpenTabsActor(persistenceURL: Self.openTabsPersistenceURL)
        self.openTabsActor = openTabsActor

        do {
            try Self.wireSync(openTabsActor: openTabsActor)
        } catch {
            let log = Logger(label: "K8sManagerApp.bootstrap")
            log.critical("Composition-root bootstrap failed: \(error)")
            fatalError("Bootstrap failed: \(error)")
        }
        Self.wireAsync()
    }

    var body: some Scene {
        K8sManagerRootScene(
            codeEditor: CodeEditorViewAdapter(),
            openTabsActor: openTabsActor
        )
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

    /// Shows a blocking NSAlert for network-volume rejection, then terminates.
    ///
    /// Mapped to `FailureCatalogue` entry F20 (non-local storage volume). The
    /// alert is modal so no main window appears before the process exits or the
    /// operator chooses a local location.
    ///
    /// - Parameter path: Human-readable storage path shown in the alert detail.
    nonisolated static func rejectNonLocalVolume(path: String) {
        let log = Logger(label: "K8sManagerApp.volumeCheck")
        log.critical("Storage path resides on a non-local volume — refusing to open database. path=\(path)")
        DispatchQueue.main.sync {
            let alert = NSAlert()
            alert.messageText = "Network Volume Detected"
            alert.informativeText =
                "K8sManager cannot use a network volume for its configuration storage. "
                + "Please move the storage directory to a local volume.\n\nPath: \(path)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Sync bootstrap

private extension K8sManagerApp {

    /// Canonical persistence path for the shared `OpenTabsActor`.
    ///
    /// TODO (ADR-0050 addendum, 2026-05-16): the canonical contract is
    /// per-cluster `clusters/<clusterId>/open-tabs.json`. Onda 3 ships this
    /// single-cluster workspace path as a transitional state — see the ADR
    /// addendum for migration plan (OpenTabsRegistry routing per ClusterId).
    nonisolated static var openTabsPersistenceURL: URL {
        ApplicationPaths.supportDirectory
            .appendingPathComponent("workspace", isDirectory: true)
            .appendingPathComponent("open-tabs.json")
    }

    /// Wires all synchronously constructible adapters and registers their ports.
    nonisolated static func wireSync(openTabsActor: OpenTabsActor) throws {
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

        // Process-wide ClusterStripActor — registered here so ClusterStripView,
        // SidebarTreeViewModel, and any other observer all share ONE actor.
        // Without this, the strip would broadcast to its own actor while the
        // sidebar silently observed a different one (two-actor split bug —
        // click on a cluster avatar would never reach the sidebar tree).
        let clusterStripActor = ClusterStripActor()

        prepareDependencies { values in
            // Domain event bus (ADR-0040)
            values.domainEventBus = domainEventBus

            // ClusterStrip — shared singleton (ADR-0051)
            values.clusterStrip = clusterStripActor

            // OpenTabs — shared singleton (ADR-0050). SidebarTreeViewModel
            // and HelmReleasesViewModel resolve this port to open document
            // tabs; the same actor backs SidebarCanvasView's tab bar.
            values.openTabs = openTabsActor

            // NamespaceFilter — process-wide picker state. Every workload
            // list view model and the canvas-header `GlobalNamespacePicker`
            // share this actor so one dropdown filters the whole app.
            values.namespaceFilter = NamespaceFilterActor()

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

            // HelmManagement extras — live adapters (ADR-0015, ADR-0046)
            wireHelmManagementExtras(db: db, into: &values)

            // PortForwarding extras — unimplemented sentinels until adapters land
            wirePortForwardingExtras(into: &values)

            // LocalPersistence + MetricsObservability extras
            wirePersistenceExtras(into: &values)
        }
    }

    /// Registers HelmManagement ports.
    ///
    /// - `rollbackLease`: Kubernetes Lease adapter (ADR-0046) via `SwiftkubeRollbackLeaseAdapter`.
    /// - `releaseDecoder`: Helm secret decoder (ADR-0015) via `HelmSecretDecoderAdapter`.
    /// - `auditLog`: Helm rollback audit log (ADR-0015) via `GRDBHelmAuditLogAdapter`.
    nonisolated static func wireHelmManagementExtras(
        db: any DatabaseWriter,
        into values: inout DependencyValues
    ) {
        let loader = YamsKubeconfigLoader()
        values.rollbackLease = SwiftkubeRollbackLeaseAdapter(resolver: buildResolver(using: loader))
        values.releaseDecoder = HelmSecretDecoderAdapter()
        values.auditLog = GRDBHelmAuditLogAdapter(db: db)
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
            await wireClusterStrip()
            await wireOpenTabs()
            await wireMCP()
            await wireLLM()
            await wireWatchCoordinator()
        }
    }

    /// Restores persisted ``ClusterStripActor`` state (pins + active cluster)
    /// from `~/Library/Application Support/K8sManager/workspace/cluster-strip-pins.json`
    /// so that the strip survives app restarts (ADR-0051).
    nonisolated static func wireClusterStrip() async {
        @Dependency(\.clusterStrip) var actor
        do {
            try await actor.loadFromDisk()
        } catch {
            let log = Logger(label: "K8sManagerApp.clusterStrip")
            log.warning("ClusterStripActor.loadFromDisk failed: \(error)")
        }
    }

    /// Restores persisted ``OpenTabsActor`` state from disk.
    ///
    /// Silently swallows `fileNotFound` on first launch; logs other errors so
    /// they remain diagnosable without crashing the bootstrap path (ADR-0050).
    nonisolated static func wireOpenTabs() async {
        @Dependency(\.openTabs) var port
        guard let actor = port as? OpenTabsActor else { return }
        do {
            try await actor.loadFromDisk()
        } catch let cocoa as CocoaError where cocoa.code == .fileReadNoSuchFile {
            // First launch — no tabs persisted yet, expected.
        } catch {
            let log = Logger(label: "K8sManagerApp.openTabs")
            log.warning("OpenTabsActor.loadFromDisk failed: \(error)")
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
