// SwiftkubePodLogsAdapter.swift — infrastructure adapter
// Bounded context: resource_browser (outbound port implementation)
// DDD role: Adapter (secondary — infrastructure)
// ADR ref: ADR-0002 (SwiftkubeClient adapter), ADR-0019 (Tier A libraries)
// Implements: PodLogsPort from ResourceBrowser

import Foundation
import ResourceBrowser
import SharedKernel
import SwiftkubeClient

// MARK: - SwiftkubePodLogsAdapter

/// `PodLogsPort` backed by `swiftkube/client`'s `follow` and `logs` APIs.
///
/// `follow=true` opens a persistent `SwiftkubeClientTask` and forwards each
/// yielded line through the `AsyncThrowingStream`. `follow=false` fetches
/// the full log blob with `logs(…)` and splits it into lines before finishing.
///
/// Thread safety: `struct` with value semantics. The composed `KubernetesClient`
/// is created per call and shut down when the continuation finishes.
public struct SwiftkubePodLogsAdapter: PodLogsPort {

    // MARK: Types

    /// Resolves a `ClusterId` to the raw connection parameters.
    public typealias ClusterResolver = @Sendable (ClusterId) async throws -> ClusterParams

    // MARK: Properties

    private let resolver: ClusterResolver

    // MARK: Init

    /// Creates the adapter with a caller-supplied cluster resolver.
    ///
    /// - Parameter resolver: Closure mapping `ClusterId` → `ClusterParams`.
    public init(resolver: @escaping ClusterResolver) {
        self.resolver = resolver
    }

    // MARK: PodLogsPort

    /// Streams log lines for the specified pod container.
    ///
    /// When `follow` is `true` the stream stays open until the caller cancels
    /// the enclosing `Task`. When `false` the stream terminates after the
    /// current log snapshot is delivered.
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
            Task {
                await runStream(
                    continuation: continuation,
                    clusterId: clusterId,
                    podName: podName,
                    namespace: namespace,
                    container: container,
                    follow: follow,
                    tailLines: tailLines,
                    previous: previous
                )
            }
        }
    }

    // MARK: Private stream runner

    private func runStream(
        continuation: AsyncThrowingStream<LogChunk, Error>.Continuation,
        clusterId: ClusterId,
        podName: String,
        namespace: String,
        container: String?,
        follow: Bool,
        tailLines: Int?,
        previous: Bool
    ) async {
        let containerName = container ?? podName

        do {
            let params = try await resolver(clusterId)
            let client = try makeClient(from: params)
            defer { try? client.syncShutdown() }

            if follow {
                try await runFollowStream(
                    client: client,
                    continuation: continuation,
                    namespace: namespace,
                    podName: podName,
                    container: container,
                    containerName: containerName,
                    tailLines: tailLines
                )
            } else {
                try await runSnapshotStream(
                    client: client,
                    continuation: continuation,
                    namespace: namespace,
                    podName: podName,
                    container: container,
                    containerName: containerName,
                    previous: previous,
                    tailLines: tailLines
                )
            }
            continuation.finish()
        } catch let error as SwiftkubeClientError {
            continuation.finish(throwing: mapClientError(error, podName: podName, namespace: namespace))
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private func runFollowStream(
        client: KubernetesClient,
        continuation: AsyncThrowingStream<LogChunk, Error>.Continuation,
        namespace: String,
        podName: String,
        container: String?,
        containerName: String,
        tailLines: Int?
    ) async throws {
        let task = try await client.pods
            .follow(
                in: .namespace(namespace),
                name: podName,
                container: container,
                timestamps: true,
                tailLines: tailLines
            )
        let stream = await task.start()
        for try await rawChunk in stream {
            guard !Task.isCancelled else { break }
            let chunk = buildChunk(raw: rawChunk, containerName: containerName)
            continuation.yield(chunk)
        }
    }

    private func runSnapshotStream(
        client: KubernetesClient,
        continuation: AsyncThrowingStream<LogChunk, Error>.Continuation,
        namespace: String,
        podName: String,
        container: String?,
        containerName: String,
        previous: Bool,
        tailLines: Int?
    ) async throws {
        let raw = try await client.pods.logs(
            in: .namespace(namespace),
            name: podName,
            container: container,
            previous: previous,
            timestamps: true,
            tailLines: tailLines
        )
        let chunk = buildChunk(raw: raw, containerName: containerName)
        continuation.yield(chunk)
    }

    // MARK: Parsing

    /// Splits a raw string chunk into `LogLine` values and wraps them in a `LogChunk`.
    func buildChunk(raw: String, containerName: String) -> LogChunk {
        let lines = raw
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { parseLine(String($0), containerName: containerName) }
        return LogChunk(
            lines: lines,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Parses one raw line into a `LogLine`, splitting an optional RFC 3339 prefix.
    func parseLine(_ raw: String, containerName: String) -> LogLine {
        let (timestamp, content) = splitTimestamp(raw)
        return LogLine(
            timestamp: timestamp,
            content: content,
            containerName: containerName,
            severity: detectSeverity(content)
        )
    }

    /// Extracts the leading RFC 3339 timestamp if present (format produced by `--timestamps`).
    ///
    /// The Kubernetes log timestamps follow the pattern `2006-01-02T15:04:05.999999999Z<space>`.
    func splitTimestamp(_ line: String) -> (String?, String) {
        let rfc3339 = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s"#
        guard let range = line.range(of: rfc3339, options: .regularExpression) else {
            return (nil, line)
        }
        let ts = String(line[range]).trimmingCharacters(in: .whitespaces)
        let rest = String(line[range.upperBound...])
        return (ts, rest)
    }

    /// Keyword-based severity detection operating on the line content.
    ///
    /// Matches common patterns used by structured loggers (logrus, zap, log4j).
    func detectSeverity(_ content: String) -> LogSeverity? {
        let upper = content.uppercased()
        if upper.contains("ERROR") || upper.contains("FATAL") || upper.contains("PANIC") {
            return .error
        }
        if upper.contains("WARN") {
            return .warning
        }
        if upper.contains(" INFO") || upper.hasPrefix("INFO") {
            return .info
        }
        if upper.contains("DEBUG") {
            return .debug
        }
        if upper.contains("TRACE") {
            return .trace
        }
        return nil
    }

    // MARK: Error mapping

    private func mapClientError(
        _ error: SwiftkubeClientError,
        podName: String,
        namespace: String
    ) -> PodLogsError {
        switch error {
        case .statusError(let status):
            let code = Int(status.code ?? 0)
            if code == 401 { return .unauthorized }
            if code == 404 { return .podNotFound(name: podName, namespace: namespace) }
            return .transportError(detail: status.message ?? "HTTP \(code)")
        case .clientError(let underlying):
            return .transportError(detail: underlying.localizedDescription)
        default:
            return .transportError(detail: "\(error)")
        }
    }

    // MARK: Client factory (mirrors SwiftkubeApiAdapter)

    private func makeClient(from params: ClusterParams) throws -> KubernetesClient {
        let authentication: KubernetesClientAuthentication
        if let token = try params.bearerToken() {
            authentication = .bearer(token: token)
        } else {
            authentication = .bearer(token: "")
        }
        let config = KubernetesClientConfig(
            masterURL: params.server,
            namespace: "default",
            authentication: authentication,
            trustRoots: try params.trustRoots(),
            insecureSkipTLSVerify: params.insecureSkipTLSVerify,
            timeout: .init(connect: .seconds(10), read: .seconds(300)),
            redirectConfiguration: .follow(max: 5, allowCycles: false)
        )
        return KubernetesClient(
            config: config,
            provider: .shared(SharedNetworking.eventLoopGroup)
        )
    }
}
