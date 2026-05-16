// ViewModels/ClusterIntelligenceViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import Foundation
import Dependencies
import Logging
import ClusterIntelligence

private let log = Logger(label: "k8smgr.app_shell.cluster_intelligence")

// MARK: - ClusterIntelligenceViewModel

/// View model for the cluster intelligence diagnostics panel.
///
/// Owned by `ClusterIntelligenceView`. Drives the MCP tool registry snapshot
/// load and the recent-invocation log load. All mutations happen on the
/// `MainActor` so SwiftUI observation coalesces updates without data races.
///
/// Both ports default to `UnimplementedMCPTransportPort` /
/// `UnimplementedMCPInvocationLogPort` when no adapter is wired; errors are
/// rendered gracefully as `.failure` in the view.
@Observable
@MainActor
public final class ClusterIntelligenceViewModel {

    // MARK: State

    /// Lifecycle state of the MCP registry snapshot load.
    public var registry: AsyncResource<MCPRegistrySnapshotReadModel> = .idle

    /// Lifecycle state of the recent invocation log load.
    public var recentInvocations: AsyncResource<MCPInvocationLogReadModel> = .idle

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.mcpTransport) private var mcpTransport

    @ObservationIgnored
    @Dependency(\.mcpInvocationLog) private var mcpInvocationLog

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads the current MCP tool registry snapshot from the transport port.
    public func loadRegistry() async {
        registry = .loading
        log.info("loadRegistry start")
        do {
            let snapshot = try await registrySnapshot()
            log.info("loadRegistry OK — version=\(snapshot.version) tools=\(snapshot.toolDescriptors.count)")
            registry = .success(snapshot)
        } catch {
            log.error("loadRegistry FAILED — \(error)")
            registry = .failure(error)
        }
    }

    /// Loads the 50 most recent MCP invocation log entries.
    public func loadRecentInvocations() async {
        recentInvocations = .loading
        log.info("loadRecentInvocations start")
        do {
            let log_ = try await mcpInvocationLog.recent(limit: 50)
            log.info("loadRecentInvocations OK — count=\(log_.entries.count)")
            recentInvocations = .success(log_)
        } catch {
            log.error("loadRecentInvocations FAILED — \(error)")
            recentInvocations = .failure(error)
        }
    }

    // MARK: Private helpers

    /// Wraps the synchronous `registrySnapshot()` call so it participates in
    /// structured concurrency and can propagate `MCPTransportError`.
    private func registrySnapshot() async throws -> MCPRegistrySnapshotReadModel {
        // registrySnapshot() is synchronous on the port; no real throw path today.
        // Wrapped in a Task hop so callers can be cancelled uniformly.
        mcpTransport.registrySnapshot()
    }
}
