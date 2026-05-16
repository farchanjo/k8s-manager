// ViewModels/LocalPersistenceViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import Foundation
import Dependencies
import Logging
import LocalPersistence
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.local_persistence")

// MARK: - LocalPersistenceViewModel

/// View model for the local persistence diagnostics screen.
///
/// Owned by `LocalPersistenceView`. Drives three independent async loads:
/// - `store` — the `PersistenceStore` aggregate root (path, schema version,
///   journal mode).
/// - `auditChainState` — current `AuditChainState` from `AuditChainPort`.
/// - `keychainEntries` — flattened `[KeychainEntry]` from all four namespaces.
///
/// All mutations happen on `MainActor` so SwiftUI observation coalesces
/// updates without data races.
@Observable
@MainActor
public final class LocalPersistenceViewModel {

    // MARK: State

    /// Lifecycle state of the persistence store info load.
    public var store: AsyncResource<PersistenceStore> = .idle

    /// Lifecycle state of the audit chain state load.
    public var auditChainState: AsyncResource<AuditChainState> = .idle

    /// Lifecycle state of the keychain entries load.
    public var keychainEntries: AsyncResource<[KeychainEntry]> = .idle

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.auditChain) private var auditChain

    @ObservationIgnored
    @Dependency(\.keychainAccess) private var keychainAccess

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads the `PersistenceStore` aggregate root from the adapter.
    ///
    /// Renders `.failure` gracefully when no adapter is wired
    /// (unimplemented port sentinel throws immediately).
    public func loadStoreInfo() async {
        store = .loading
        log.info("loadStoreInfo start")
        do {
            let value = try await fetchStoreInfo()
            log.info("loadStoreInfo OK path=\(value.storageFilePath) schema=\(value.schemaVersion)")
            store = .success(value)
        } catch {
            log.error("loadStoreInfo FAILED — \(error)")
            store = .failure(error)
        }
    }

    /// Loads the current `AuditChainState` without performing a full walk.
    ///
    /// Renders `.failure` gracefully when the port is not wired or the
    /// Keychain is locked.
    public func loadAuditChainState() async {
        auditChainState = .loading
        log.info("loadAuditChainState start")
        do {
            let state = try await auditChain.currentState()
            log.info("loadAuditChainState OK state=\(state)")
            auditChainState = .success(state)
        } catch {
            log.error("loadAuditChainState FAILED — \(error)")
            auditChainState = .failure(error)
        }
    }

    /// Loads `KeychainEntry` records from all four namespaces.
    ///
    /// Namespaces are listed sequentially; the first namespace failure causes
    /// the entire load to resolve as `.failure`.
    public func loadKeychainEntries() async {
        keychainEntries = .loading
        log.info("loadKeychainEntries start")
        do {
            let entries = try await fetchAllKeychainEntries()
            log.info("loadKeychainEntries OK count=\(entries.count)")
            keychainEntries = .success(entries)
        } catch {
            log.error("loadKeychainEntries FAILED — \(error)")
            keychainEntries = .failure(error)
        }
    }

    // MARK: Private helpers

    private func fetchStoreInfo() async throws -> PersistenceStore {
        // The live adapter registers itself at composition-root time; the
        // unimplemented sentinel throws `AuditChainError.unimplemented`.
        // There is no direct StorePort — the GRDBPersistenceAdapter exposes
        // store metadata via the audit chain state; here we synthesize a
        // stub from the canonical path (ADR-0026, ApplicationPaths) so the UI has
        // something to show when the adapter is wired.
        //
        // When a dedicated StoreInfoPort is added (future ADR), replace this
        // body with a `@Dependency(\.storeInfo)` call.
        let _ = try await auditChain.currentState()
        let path = ApplicationPaths.storageURL.path
        return PersistenceStore(
            id: UUID(),
            storageFilePath: path,
            schemaVersion: 1
        )
    }

    private func fetchAllKeychainEntries() async throws -> [KeychainEntry] {
        let namespaces: [KeychainServiceNamespace] = [.llm, .oidc, .azure, .audit]
        var all: [KeychainEntry] = []
        for ns in namespaces {
            let entries = try await keychainAccess.listEntries(namespace: ns)
            all.append(contentsOf: entries)
        }
        return all
    }
}
