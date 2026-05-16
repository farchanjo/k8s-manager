// ViewModels/PodLogsViewModel.swift — app_shell bounded context
// DDD role: ViewModel — pod log streaming tab
// ADR ref: ADR-0050 (tab system), Onda 3

import Foundation
import Observation
import Dependencies
import Logging
import ResourceBrowser
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.pod_logs")

// MARK: - PodLogsViewModel

/// View model for `PodLogsTab`.
///
/// Owns the `AsyncThrowingStream` subscription lifecycle, the ring-buffer
/// of `LogLine` values (capped at `maxBufferSize`), and all toolbar state.
/// Actor-isolated to `@MainActor` via `@Observable`.
@Observable
@MainActor
public final class PodLogsViewModel {

    // MARK: Published state

    /// All lines currently in the ring buffer (≤ `maxBufferSize`).
    public var lines: [LogLine] = []

    /// Whether the view auto-scrolls to the newest line.
    public var follow: Bool = true

    /// Word-wrap toggle for the scroll view.
    public var wrap: Bool = true

    /// Maximum tail-lines to request on connect. `nil` = all.
    public var tailLines: Int? = 1_000

    /// Timestamp prefix toggle.
    public var showTimestamps: Bool = true

    /// Current search / filter query.
    public var searchQuery: String = ""

    /// Severity filter chips (empty = show all).
    public var severityFilter: Set<LogSeverity> = []

    /// Currently displayed container name (first container by default).
    public var selectedContainer: String?

    /// All container names available in the pod spec.
    public var availableContainers: [String] = []

    /// Load state for the toolbar streaming indicator.
    public var loadState: AsyncResource<Void> = .idle

    /// When `true` the stream is temporarily suspended.
    public var isPaused: Bool = false

    // MARK: Derived

    /// Lines after applying `searchQuery` and `severityFilter`.
    public var filteredLines: [LogLine] {
        var result = lines
        if !searchQuery.isEmpty {
            result = result.filter { $0.content.localizedCaseInsensitiveContains(searchQuery) }
        }
        if !severityFilter.isEmpty {
            result = result.filter { line in
                guard let sev = line.severity else { return false }
                return severityFilter.contains(sev)
            }
        }
        return result
    }

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.podLogs) private var logsPort

    // MARK: Private state

    @ObservationIgnored private var streamTask: Task<Void, Never>?

    @ObservationIgnored private var resumeInfo: (ClusterId, String, String, String?)?

    /// Maximum number of log lines retained in `lines`.
    let maxBufferSize = 10_000

    // MARK: Init

    public init() {}

    // MARK: Lifecycle

    /// Begins streaming logs for the given pod and (optional) container.
    ///
    /// Stores resume coordinates so `resume()` can restart the stream
    /// after a `pause()` without requiring new parameters.
    public func start(clusterId: ClusterId, podRef: ResourceRef, container: String?) async {
        let podName = podRef.name
        let namespace = podRef.namespace ?? "default"
        resumeInfo = (clusterId, podName, namespace, container)
        selectedContainer = container
        await beginStreaming(clusterId: clusterId, podName: podName, namespace: namespace, container: container)
    }

    // MARK: Controls

    /// Suspends the stream and marks `isPaused = true`.
    public func pause() {
        streamTask?.cancel()
        streamTask = nil
        isPaused = true
        log.info("log stream paused")
    }

    /// Resumes from the last `start` coordinates.
    public func resume() async {
        guard let (cid, podName, namespace, container) = resumeInfo else { return }
        isPaused = false
        await beginStreaming(clusterId: cid, podName: podName, namespace: namespace, container: container)
    }

    /// Clears the in-memory buffer and resets the load state.
    public func clearBuffer() {
        lines = []
        loadState = .idle
        log.info("log buffer cleared")
    }

    /// Exports the current buffer as a UTF-8 `.log` file in the temp directory.
    ///
    /// Returns the file URL on success, or `nil` if the write failed.
    public func exportLogs() async -> URL? {
        let text = lines.map { line -> String in
            var parts: [String] = []
            if let ts = line.timestamp { parts.append(ts) }
            parts.append("[\(line.containerName)]")
            parts.append(line.content)
            return parts.joined(separator: " ")
        }.joined(separator: "\n")

        let name = "k8s-logs-\(Date().timeIntervalSince1970).log"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            log.info("exported logs url=\(url.lastPathComponent)")
            return url
        } catch {
            log.error("export failed — \(error)")
            return nil
        }
    }

    // MARK: Private helpers

    private func beginStreaming(
        clusterId: ClusterId,
        podName: String,
        namespace: String,
        container: String?
    ) async {
        streamTask?.cancel()
        loadState = .loading

        let stream = logsPort.streamLogs(
            clusterId: clusterId,
            podName: podName,
            namespace: namespace,
            container: container,
            follow: follow,
            tailLines: tailLines,
            sinceSeconds: nil,
            previous: false
        )

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await chunk in stream {
                    guard !Task.isCancelled else { break }
                    self.appendChunk(chunk)
                    if self.loadState.isLoading {
                        self.loadState = .success(())
                    }
                }
            } catch {
                self.loadState = .failure(error)
                log.error("stream error — \(error)")
            }
        }
    }

    /// Appends chunk lines and rotates the buffer when `maxBufferSize` is exceeded.
    private func appendChunk(_ chunk: LogChunk) {
        lines.append(contentsOf: chunk.lines)
        if lines.count > maxBufferSize {
            lines.removeFirst(lines.count - maxBufferSize)
        }
    }
}
