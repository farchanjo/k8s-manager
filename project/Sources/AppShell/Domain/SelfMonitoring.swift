// Domain/SelfMonitoring.swift — app_shell bounded context
// DDD role: AggregateRoot (#SelfMonitoringState), Entity (#SelfMetricSample),
//           ValueObject (#DiagnosticsBundle)
// CUE source: docs/arch/contexts/app_shell/schemas/self_monitoring.cue
// ADR ref: ADR-0027

import Foundation

// MARK: - SelfMonitoringState (AggregateRoot)

/// Persisted operator preferences for the app self-monitoring sub-domain.
///
/// Persisted under `app_shell/self_monitoring_state` in `local_persistence`.
public struct SelfMonitoringState: Sendable, Codable, Identifiable {
    public enum SampleInterval: Int, Sendable, Codable {
        case one = 1, five = 5, fifteen = 15, thirty = 30, sixty = 60
    }

    /// UUIDv7 stable identity.
    public let id: String
    /// How often `SelfMonitoringSampler` collects a snapshot.
    public var sampleIntervalSeconds: SampleInterval
    /// When `true`, the self-monitoring widget appears in the menu bar tray.
    public var surfaceInTray: Bool
    /// Duration of the in-memory ring buffer in minutes [1, 1440].
    public var retentionMinutes: Int
    /// When `true`, `DiagnosticsBundleExporter` may access the 24 h SQLite history.
    public var exportEnabled: Bool

    public init(
        id: String,
        sampleIntervalSeconds: SampleInterval = .five,
        surfaceInTray: Bool = false,
        retentionMinutes: Int = 60,
        exportEnabled: Bool = true
    ) {
        self.id = id
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.surfaceInTray = surfaceInTray
        self.retentionMinutes = retentionMinutes
        self.exportEnabled = exportEnabled
    }
}

// MARK: - SelfMetricSample (Entity)

/// One snapshot collected by `SelfMonitoringSampler` at a single timestamp.
///
/// Fields unavailable in the App Sandbox degrade to `-1` (sentinel). Never causes
/// a crash or an invalid sample record per the App Sandbox invariant.
public struct SelfMetricSample: Sendable, Codable, Identifiable {
    public let id: UUID
    /// RFC 3339 timestamp at which the sample was taken.
    public let timestampRFC3339: String
    public let cpuUsagePercent: Double
    public let memoryRSSBytes: Int
    public let memoryPeakRSSBytes: Int
    public let threadCount: Int
    public let fileDescriptorCount: Int
    public let networkBytesIn: Int
    public let networkBytesOut: Int
    public let activeWatchStreams: Int
    public let activeExecSessions: Int
    public let activePortForwards: Int
    public let activeChatStreams: Int
    public let sqliteSizeBytes: Int
    public let cacheSizeBytes: Int
    public let actorCount: Int
    public let eventLoopGroupCount: Int
    public let kqueueEventsPerSecond: Double?

    public init(
        id: UUID = UUID(),
        timestampRFC3339: String,
        cpuUsagePercent: Double,
        memoryRSSBytes: Int, memoryPeakRSSBytes: Int,
        threadCount: Int, fileDescriptorCount: Int,
        networkBytesIn: Int, networkBytesOut: Int,
        activeWatchStreams: Int, activeExecSessions: Int,
        activePortForwards: Int, activeChatStreams: Int,
        sqliteSizeBytes: Int, cacheSizeBytes: Int,
        actorCount: Int, eventLoopGroupCount: Int,
        kqueueEventsPerSecond: Double? = nil
    ) {
        self.id = id
        self.timestampRFC3339 = timestampRFC3339
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryRSSBytes = memoryRSSBytes
        self.memoryPeakRSSBytes = memoryPeakRSSBytes
        self.threadCount = threadCount
        self.fileDescriptorCount = fileDescriptorCount
        self.networkBytesIn = networkBytesIn
        self.networkBytesOut = networkBytesOut
        self.activeWatchStreams = activeWatchStreams
        self.activeExecSessions = activeExecSessions
        self.activePortForwards = activePortForwards
        self.activeChatStreams = activeChatStreams
        self.sqliteSizeBytes = sqliteSizeBytes
        self.cacheSizeBytes = cacheSizeBytes
        self.actorCount = actorCount
        self.eventLoopGroupCount = eventLoopGroupCount
        self.kqueueEventsPerSecond = kqueueEventsPerSecond
    }

    /// Sentinel value indicating a field is unavailable in the App Sandbox.
    public static let unavailableSentinel = -1
}

// MARK: - DiagnosticsBundle (ValueObject)

/// Metadata record embedded as `bundle-manifest.json` inside every exported diagnostics zip.
///
/// Created by `DiagnosticsBundleExporter`; immutable after the bundle is sealed.
public struct DiagnosticsBundle: Sendable, Codable, Identifiable {
    /// UUIDv7 for deduplication in support workflows.
    public let id: String
    public var bundleId: String { id }
    /// RFC 3339 timestamp at which the exporter sealed the zip.
    public let generatedAtRFC3339: String
    /// Number of `SelfMetricSample` records in `metrics/self-metrics-24h.json`.
    public let sampleCount: Int
    /// Log file names included under `logs/` (after redaction).
    public let logFilesIncluded: [String]
    /// Total uncompressed size in bytes before zipping.
    public let totalSizeBytes: Int
    /// `true` when the log redactor confirmed no credential patterns remain.
    /// Exporter aborts if this would be `false`.
    public let redactionApplied: Bool

    public init(
        bundleId: String,
        generatedAtRFC3339: String,
        sampleCount: Int,
        logFilesIncluded: [String],
        totalSizeBytes: Int,
        redactionApplied: Bool = true
    ) {
        self.id = bundleId
        self.generatedAtRFC3339 = generatedAtRFC3339
        self.sampleCount = sampleCount
        self.logFilesIncluded = logFilesIncluded
        self.totalSizeBytes = totalSizeBytes
        self.redactionApplied = redactionApplied
    }
}
