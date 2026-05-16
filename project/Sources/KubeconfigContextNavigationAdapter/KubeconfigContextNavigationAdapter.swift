// KubeconfigContextNavigationAdapter.swift — kubeconfig_context_navigation_adapter
// DDD role: Adapter (anti-corruption layer bridging ClusterConnectivity + LocalPersistence
// into the ContextNavigation bounded context).
// ADR ref: ADR-0020 (composition root as the only importer of infrastructure adapters).

import Foundation
import Logging

import ClusterConnectivity
import ContextNavigation
import LocalPersistence
import SharedKernel

// MARK: - KubeconfigContextRepository

/// `ContextRepositoryPort` backed by the kubeconfig file and GRDB metadata store.
///
/// Pins and recents are scoped to the in-process `Actor`-isolated store; `lastActiveContext`
/// is persisted across launches via `ClusterMetadataStorePort` using a well-known synthetic
/// `clusterId` (a stable UUID derived from `"context-navigation.active-context"`).
public struct KubeconfigContextRepository: ContextRepositoryPort {

    private static let activeContextClusterId = UUID(uuidString: "00000000-0000-0000-0000-000000000ACE")!
    private static let activeContextAnalysisKind: AnalysisKind = .clusterSummary

    private let loader: any KubeconfigLoaderPort
    private let metadataStore: any ClusterMetadataStorePort
    private let log: Logger
    // In-process mutable state for pins/recents. Actor wrapping lives in watch.
    private let state: RepositoryState

    public init(
        loader: any KubeconfigLoaderPort,
        metadataStore: any ClusterMetadataStorePort,
        logger: Logger = Logger(label: "KubeconfigContextRepository")
    ) {
        self.loader = loader
        self.metadataStore = metadataStore
        self.log = logger
        self.state = RepositoryState()
    }

    // MARK: Recents

    public func loadRecentWindow() async throws -> RecentContextWindow {
        await state.recentWindow()
    }

    public func saveRecentWindow(_ window: RecentContextWindow) async throws {
        await state.setRecentWindow(window)
    }

    // MARK: Pins

    public func loadPinnedContexts() async throws -> [PinnedContext] {
        await state.pinnedContexts()
    }

    public func pin(_ context: PinnedContext) async throws {
        await state.insertPin(context)
    }

    public func unpin(contextId: ContextId) async throws {
        await state.removePin(contextId: contextId)
    }

    // MARK: Last active context

    public func loadLastActiveContext() async throws -> ActiveContext? {
        let entry = try await metadataStore.cachedAnalysis(
            clusterId: Self.activeContextClusterId,
            kind: Self.activeContextAnalysisKind,
            now: Date()
        )
        guard let entry else { return nil }
        return try decodeActiveContext(from: entry.payloadJSON)
    }

    public func saveLastActiveContext(_ context: ActiveContext) async throws {
        let json = try encodeActiveContext(context)
        let entry = ClusterAnalysisCache(
            id: UUID(),
            clusterId: Self.activeContextClusterId,
            kind: Self.activeContextAnalysisKind,
            payloadJSON: json,
            expiresAt: Date.distantFuture,
            createdAt: Date()
        )
        try await metadataStore.upsertAnalysis(entry)
        log.debug("Persisted active context: \(context.contextId?.rawValue ?? "<nil>")")
    }

    // MARK: Private helpers

    private func encodeActiveContext(_ context: ActiveContext) throws -> String {
        let data = try JSONEncoder().encode(context)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ContextRepositoryError.storageError(underlying: "UTF-8 encoding failed")
        }
        return json
    }

    private func decodeActiveContext(from json: String) throws -> ActiveContext {
        guard let data = json.data(using: .utf8) else {
            throw ContextRepositoryError.decodeError(detail: "Non-UTF-8 payload")
        }
        do {
            return try JSONDecoder().decode(ActiveContext.self, from: data)
        } catch {
            throw ContextRepositoryError.decodeError(detail: error.localizedDescription)
        }
    }
}

// MARK: - RepositoryState

/// Actor-isolated in-process state for pins and recents.
///
/// `@unchecked Sendable` is NOT used here — actor provides full isolation.
private actor RepositoryState {
    private var window = RecentContextWindow()
    private var pins: [ContextId: PinnedContext] = [:]

    func recentWindow() -> RecentContextWindow { window }
    func setRecentWindow(_ w: RecentContextWindow) { window = w }

    func pinnedContexts() -> [PinnedContext] {
        pins.values.sorted { $0.displayOrder < $1.displayOrder }
    }

    func insertPin(_ pin: PinnedContext) { pins[pin.contextId] = pin }
    func removePin(contextId: ContextId) { pins.removeValue(forKey: contextId) }
}

// MARK: - KubeconfigActiveContextWatch

/// `ActiveContextWatchPort` that streams `ActiveContextChanged` events to consumers.
///
/// Initial value is resolved at subscription time: persisted override wins over
/// the kubeconfig `currentContext` fallback.
public actor KubeconfigActiveContextWatch: ActiveContextWatchPort {

    private let repository: KubeconfigContextRepository
    private let loader: any KubeconfigLoaderPort
    private let log: Logger
    private var continuations: [UUID: AsyncThrowingStream<ActiveContextChanged, Error>.Continuation] = [:]
    private var current: ActiveContext = ActiveContext()

    public init(
        repository: KubeconfigContextRepository,
        loader: any KubeconfigLoaderPort,
        logger: Logger = Logger(label: "KubeconfigActiveContextWatch")
    ) {
        self.repository = repository
        self.loader = loader
        self.log = logger
    }

    // MARK: ActiveContextWatchPort

    public nonisolated func watchActiveContextChanges() -> AsyncThrowingStream<ActiveContextChanged, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.subscribe(continuation: continuation) }
        }
    }

    // MARK: Internal — called by composition root after selection

    /// Advances the active context and fans out an event to all subscribers.
    public func select(contextId: ContextId, origin: SelectionOrigin) async {
        let clock = SystemClock()
        let (next, event) = ContextSwitcher.select(
            current: current,
            newContextId: contextId,
            origin: origin,
            clock: clock
        )
        guard let event else { return }
        current = next
        try? await repository.saveLastActiveContext(next)
        for continuation in continuations.values { continuation.yield(event) }
        log.info("Active context changed to: \(contextId.rawValue)")
    }

    // MARK: Private

    private func subscribe(
        continuation: AsyncThrowingStream<ActiveContextChanged, Error>.Continuation
    ) async {
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id: id) }
        }
        await emitInitialEvent(to: continuation)
    }

    private func emitInitialEvent(
        to continuation: AsyncThrowingStream<ActiveContextChanged, Error>.Continuation
    ) async {
        let resolved = await resolveInitialContext()
        let event = ActiveContextChanged(previous: nil, next: resolved)
        current = resolved
        continuation.yield(event)
    }

    private func resolveInitialContext() async -> ActiveContext {
        if let persisted = try? await repository.loadLastActiveContext(), persisted.contextId != nil {
            return ActiveContext(
                id: persisted.id,
                contextId: persisted.contextId,
                selectedAtRFC3339: persisted.selectedAtRFC3339,
                selectedBy: .restored
            )
        }
        return await fallbackFromKubeconfig()
    }

    private func fallbackFromKubeconfig() async -> ActiveContext {
        do {
            let config = try await loader.load(from: KubeconfigPath("~/.kube/config"))
            if let active = loader.activeContext(in: config) {
                return ActiveContext(contextId: ContextId(active.name), selectedBy: .fallback)
            }
        } catch {
            log.warning("Kubeconfig load failed during active-context fallback: \(error)")
        }
        return ActiveContext()
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

// MARK: - KubeconfigSidebarReadModel

/// `SidebarReadModelPort` that assembles the sidebar projection from the repository.
public struct KubeconfigSidebarReadModel: SidebarReadModelPort {

    private let repository: KubeconfigContextRepository
    private let watch: KubeconfigActiveContextWatch
    private let log: Logger

    public init(
        repository: KubeconfigContextRepository,
        watch: KubeconfigActiveContextWatch,
        logger: Logger = Logger(label: "KubeconfigSidebarReadModel")
    ) {
        self.repository = repository
        self.watch = watch
        self.log = logger
    }

    // MARK: SidebarReadModelPort

    public func currentSidebar() async throws -> SidebarReadModel {
        let pins = try await repository.loadPinnedContexts()
        let window = try await repository.loadRecentWindow()
        let pinnedIds = Set(pins.map(\.contextId))
        let recents = window.entries.filter { !pinnedIds.contains($0.contextId) }
        return SidebarReadModel(pinned: pins, recents: recents)
    }

    public func watchSidebar() -> AsyncThrowingStream<SidebarReadModel, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let initial = try await currentSidebar()
                    continuation.yield(initial)
                    for try await _ in watch.watchActiveContextChanges() {
                        let updated = try await currentSidebar()
                        continuation.yield(updated)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

