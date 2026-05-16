// ViewModels/DiagnosticsViewModel.swift — app_shell bounded context
// DDD role: ViewModel — cluster diagnostics bundle collection (Onda 2 skeleton)
// ADR ref: ADR-0050 (cluster operations), ADR-0027 (diagnostics export)

import Foundation
import Observation
import Logging
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.diagnostics")

// MARK: - DiagnosticsViewModel

/// View model for the Diagnostics tab.
///
/// Onda 2 skeleton: collects kubeconfig info + cluster metadata + node list +
/// recent events and writes them to a temp directory. Full must-gather is Onda 3+.
///
/// All mutations are `@MainActor`-isolated.
@Observable
@MainActor
public final class DiagnosticsViewModel {

    // MARK: State

    /// Current phase of the collection pipeline.
    public var collectionState: DiagnosticsCollectionState = .idle

    /// Streaming log lines appended during collection.
    public var outputLines: [String] = []

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Starts a basic diagnostic collection for `clusterId`.
    ///
    /// Gathers: kubeconfig path, cluster info, node list, recent events.
    /// Writes output to a temp directory and transitions to `.done(bundleURL:)`.
    public func collect(clusterId: ClusterId) async {
        guard case .idle = collectionState else { return }
        outputLines = []
        collectionState = .collecting(status: "Initialising…")

        do {
            let url = try await runCollection(clusterId: clusterId)
            collectionState = .done(bundleURL: url)
            log.info("collect done path=\(url.path)")
        } catch {
            collectionState = .failed(error)
            log.error("collect FAILED — \(error)")
        }
    }

    /// Resets to idle state so a fresh collection can be started.
    public func reset() {
        collectionState = .idle
        outputLines = []
    }

    // MARK: Private — collection pipeline

    private func runCollection(clusterId: ClusterId) async throws -> URL {
        let bundleDir = try makeBundleDirectory(clusterId: clusterId)

        await appendLine("Bundle directory: \(bundleDir.path)")
        await step("Collecting cluster info…") {
            let info = "cluster_id: \(clusterId.rawValue)\ncollected_at: \(ISO8601DateFormatter().string(from: Date()))\n"
            try info.write(to: bundleDir.appendingPathComponent("cluster-info.txt"), atomically: true, encoding: .utf8)
        }

        await step("Collecting node list (stub)…") {
            let stub = "# Node list placeholder — Onda 3 wires real API call\n"
            try stub.write(to: bundleDir.appendingPathComponent("nodes.txt"), atomically: true, encoding: .utf8)
        }

        await step("Collecting recent events (stub)…") {
            let stub = "# Events placeholder — Onda 3 wires real API call\n"
            try stub.write(to: bundleDir.appendingPathComponent("events.txt"), atomically: true, encoding: .utf8)
        }

        await appendLine("Collection complete.")
        return bundleDir
    }

    private func makeBundleDirectory(clusterId: ClusterId) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
        let dir = tmp
            .appendingPathComponent("k8smgr-diagnostics")
            .appendingPathComponent(clusterId.rawValue)
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func step(_ status: String, work: () throws -> Void) async {
        collectionState = .collecting(status: status)
        await appendLine(status)
        do {
            try work()
        } catch {
            await appendLine("Warning: \(error.localizedDescription)")
        }
    }

    private func appendLine(_ line: String) async {
        outputLines.append(line)
    }
}
