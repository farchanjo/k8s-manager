// Actors/ReleaseReaderActor.swift — helm_management bounded context
// DDD role: DomainService (Swift actor — release enumeration + history projection)
// ADR ref: ADR-0015 §Phase 1 §Grouping revisions

import Dependencies
import Foundation
import SharedKernel

// MARK: - ReleaseReaderActor

/// Orchestrates enumeration of `helm.sh/release.v1` Secrets, caches decoded
/// `Release` aggregates keyed by namespace, and projects `ReleaseHistoryEntry`
/// read models from grouped revisions.
///
/// Cache invalidation is explicit — call `refresh()` whenever the operator
/// navigates to a new cluster context or requests a forced reload. The actor
/// boundary guarantees all cache mutations are race-free under Swift 6 strict
/// concurrency without additional locking.
///
/// The domain core never imports infrastructure modules; all cluster access
/// is mediated through `@Dependency(\.helmReleaseStore)`.
public actor ReleaseReaderActor {

    // MARK: State

    /// Cache: namespace → sorted list of decoded release revisions.
    ///
    /// The outer key is the Kubernetes namespace string; the inner array
    /// contains every revision for that namespace (all statuses) sorted by
    /// `(name, version)` ascending. `ReleaseReaderActor` never exposes raw
    /// cache entries — callers receive projected read models.
    private var cachedReleases: [String: [Release]] = [:]

    // MARK: Init

    /// Creates a `ReleaseReaderActor` with an empty cache.
    ///
    /// Dependencies are resolved lazily via `@Dependency` on each call so
    /// that test overrides registered with `withDependencies` are respected.
    public init() {}

    // MARK: - list(in:)

    /// Lists all decoded Helm release aggregates visible in `clusterId`,
    /// optionally scoped to a single namespace.
    ///
    /// Cache hit: returns the cached slice for `namespace` without a cluster
    /// round-trip. Cache miss: fetches from `helmReleaseStore`, populates
    /// the cache, then returns the result.
    ///
    /// - Parameters:
    ///   - clusterId: Stable identifier of the active cluster context.
    ///   - namespace: Kubernetes namespace to list. Pass `nil` to fetch
    ///     across all namespaces visible to the operator's credentials.
    /// - Returns: All decodable release revisions for the given namespace.
    /// - Throws: `HelmReleaseStoreError` on transport or decode failure.
    public func list(in clusterId: ClusterId, namespace: String? = nil) async throws -> [Release] {
        let key = namespace ?? "*"
        if let cached = cachedReleases[key] {
            return cached
        }
        @Dependency(\.helmReleaseStore) var store
        let releases = try await store.listReleases(clusterId: clusterId, namespace: namespace)
        cachedReleases[key] = releases
        return releases
    }

    // MARK: - history(for:)

    /// Returns the full revision history for a single logical Helm release.
    ///
    /// Projects `ReleaseHistoryEntry` values from all revisions whose
    /// `(name, namespace)` tuple matches `releaseId`. Revisions are sorted
    /// ascending by `version`. The caller must have previously populated the
    /// cache via `list(in:namespace:)` or the method fetches all-namespace
    /// releases from the store.
    ///
    /// - Parameters:
    ///   - releaseId: The `Release.id` of any revision belonging to the
    ///     logical release (the actor resolves the full history by name+namespace).
    ///   - clusterId: Stable identifier of the active cluster context.
    /// - Returns: Ordered history entries from revision 1 to the latest.
    /// - Throws: `HelmReleaseStoreError` when a fetch is required and fails.
    public func history(for releaseId: UUID, clusterId: ClusterId) async throws -> [ReleaseHistoryEntry] {
        let allReleases = try await allCached(clusterId: clusterId)
        guard let target = allReleases.first(where: { $0.id == releaseId }) else {
            return []
        }
        let revisions = allReleases
            .filter { $0.name == target.name && $0.namespace == target.namespace }
            .sorted { $0.version < $1.version }
        return revisions.map { ReleaseHistoryEntry(
            revision: $0.version,
            deployedAtRFC3339: $0.modifiedAtRFC3339,
            status: $0.status,
            chartVersion: $0.chart.version,
            appVersion: $0.chart.appVersion,
            description: $0.info.description,
            supersededAtRFC3339: $0.status == .superseded ? $0.modifiedAtRFC3339 : nil
        )}
    }

    // MARK: - refresh()

    /// Invalidates the entire release cache.
    ///
    /// Call this when the operator switches cluster contexts, triggers a manual
    /// reload, or when an event (e.g., rollback completion) signals that cluster
    /// state has changed. The next call to `list(in:)` will perform a fresh
    /// cluster round-trip.
    public func refresh() {
        cachedReleases.removeAll()
    }

    // MARK: - Private helpers

    private func allCached(clusterId: ClusterId) async throws -> [Release] {
        let key = "*"
        if let cached = cachedReleases[key] {
            return cached
        }
        @Dependency(\.helmReleaseStore) var store
        let releases = try await store.listReleases(clusterId: clusterId, namespace: nil)
        cachedReleases[key] = releases
        return releases
    }
}
