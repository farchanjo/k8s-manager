// Ports/PodLogsPort.swift — resource_browser bounded context
// DDD role: Port (outbound — pod log streaming)
// ADR ref: ADR-0013 (logs subresource), ADR-0020 (DI strategy)

import Foundation
import SharedKernel

// MARK: - LogSeverity

/// Best-effort severity extracted from a log line's textual content.
///
/// Parsed via keyword matching (ERROR, WARN, INFO, DEBUG, TRACE).
/// `nil` means no severity marker was detected in the line.
/// UI color mapping lives in `AppShell` as a `SwiftUI.Color` extension.
public enum LogSeverity: String, Sendable, Hashable, Equatable, CaseIterable {
    case error
    case warning
    case info
    case debug
    case trace
}

// MARK: - LogLine

/// A single parsed line from a pod log stream.
///
/// `Identifiable` via a stable `UUID` generated at parse time so that
/// `LazyVStack` can diff and recycle rows without comparing full content strings.
public struct LogLine: Sendable, Hashable, Identifiable {
    /// Stable row identity for SwiftUI diffing.
    public let id: UUID
    /// RFC 3339 timestamp prefix when `--timestamps=true` was requested.
    /// `nil` when the line carries no timestamp (e.g. raw stderr output).
    public let timestamp: String?
    /// The log text after stripping the optional timestamp prefix.
    public let content: String
    /// Name of the container that produced this line.
    ///
    /// Used as a badge when the pod has more than one container.
    public let containerName: String
    /// Best-effort severity inferred from the line content.
    public let severity: LogSeverity?

    public init(
        id: UUID = UUID(),
        timestamp: String?,
        content: String,
        containerName: String,
        severity: LogSeverity?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.containerName = containerName
        self.severity = severity
    }
}

// MARK: - LogChunk

/// A batch of `LogLine` values emitted in a single stream iteration.
///
/// Grouping lines into chunks reduces the number of `continuation.yield` calls
/// when the server sends a large burst of output, improving throughput.
public struct LogChunk: Sendable, Hashable {
    /// One or more parsed log lines.
    public let lines: [LogLine]
    /// ISO 8601 timestamp marking when this chunk was received by the adapter.
    public let timestamp: String

    public init(lines: [LogLine], timestamp: String) {
        self.lines = lines
        self.timestamp = timestamp
    }
}

// MARK: - PodLogsError

/// Domain errors raised by `PodLogsPort` implementations.
public enum PodLogsError: Error, Sendable {
    /// The named pod does not exist in the specified namespace.
    case podNotFound(name: String, namespace: String)
    /// The named container does not exist in the pod.
    case containerNotFound(container: String, pod: String)
    /// The cluster rejected the request with HTTP 401.
    case unauthorized
    /// A transport-level failure (TLS, TCP, timeout).
    case transportError(detail: String)
    /// Port not yet registered in this process.
    case unimplemented
}

// MARK: - PodLogsPort

/// Streams container log lines from a running or terminated pod.
///
/// Declared in the domain core; implemented by `SwiftkubeClientAdapter`
/// in the infrastructure layer.
///
/// The caller receives an `AsyncThrowingStream` that emits `LogChunk`
/// values until the server closes the stream (follow=false reaches EOF,
/// follow=true runs until cancelled) or an error is thrown.
public protocol PodLogsPort: Sendable {

    /// Opens a log stream for the given pod reference.
    ///
    /// - Parameters:
    ///   - clusterId: The active cluster identifier.
    ///   - podRef: Lightweight reference carrying kind, namespace, and name.
    ///   - container: Container name. `nil` selects the first container.
    ///   - follow: When `true`, stream continues as new lines arrive.
    ///   - tailLines: Limit on lines returned before following. `nil` = all.
    ///   - sinceSeconds: Return only logs newer than this many seconds.
    ///   - previous: Return logs from the previously terminated instance.
    /// - Returns: An `AsyncThrowingStream<LogChunk, Error>`.
    func streamLogs(
        clusterId: ClusterId,
        podName: String,
        namespace: String,
        container: String?,
        follow: Bool,
        tailLines: Int?,
        sinceSeconds: Int?,
        previous: Bool
    ) -> AsyncThrowingStream<LogChunk, Error>
}

// MARK: - UnimplementedPodLogsPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedPodLogsPort: PodLogsPort {
    public init() {}

    public func streamLogs(
        clusterId: ClusterId,
        podName: String,
        namespace: String,
        container: String?,
        follow: Bool,
        tailLines: Int?,
        sinceSeconds: Int?,
        previous: Bool
    ) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: PodLogsError.unimplemented)
        }
    }
}
