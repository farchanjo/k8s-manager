// Domain/Services/DiagnosticsBundleExporter.swift — app_shell bounded context
// DDD role: DomainService
// ADR ref: ADR-0027

import Foundation

// MARK: - ExportError

/// Typed errors for the diagnostics bundle export pipeline.
public enum ExportError: Error, Sendable {
    /// A log-redaction step failed; the export is aborted (fail-safe invariant).
    case redactionFailed(String)
    /// The SQLite history query returned no data.
    case noSamplesAvailable
    /// The destination directory could not be created.
    case destinationUnavailable(String)
    /// Zip archive creation failed.
    case archiveFailed(String)
}

// MARK: - DiagnosticsBundleExporter

/// Packages the 24 h SQLite history of `SelfMetricSample` records and sanitized log files
/// into a zip at `~/.config/k8smanager/exports/`.
///
/// Invariants:
/// - Aborts the entire export if any redaction step fails (fail-safe).
/// - Never writes a partial bundle.
/// - No credential material appears in the exported manifest.
public struct DiagnosticsBundleExporter: Sendable {

    private let exportDirectory: URL
    private let redactor: any LogRedactor

    public init(exportDirectory: URL, redactor: any LogRedactor) {
        self.exportDirectory = exportDirectory
        self.redactor = redactor
    }

    /// Exports a diagnostics bundle and returns the sealed `DiagnosticsBundle` manifest.
    ///
    /// - Parameters:
    ///   - samples: `SelfMetricSample` records from the 24 h SQLite history.
    ///   - logFiles: Map of filename → raw log content to redact and include.
    /// - Returns: Immutable `DiagnosticsBundle` manifest embedded as `bundle-manifest.json`.
    /// - Throws: `ExportError` on any failure; no partial bundle is written.
    public func export(
        samples: [SelfMetricSample],
        logFiles: [String: String]
    ) async throws(ExportError) -> DiagnosticsBundle {
        guard !samples.isEmpty else { throw .noSamplesAvailable }

        let bundleId = UUID().uuidString
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var redactedLogs: [String: String] = [:]

        // Redact every log file — abort on first failure (fail-safe invariant).
        for (name, content) in logFiles {
            guard let redacted = await redactor.redact(content) else {
                throw .redactionFailed("Log redaction failed for file: \(name)")
            }
            redactedLogs["\(name).redacted"] = redacted
        }

        let destination = exportDirectory
            .appendingPathComponent("diagnostics-\(bundleId).zip")

        try ensureDirectory()

        let totalSize = calculateSize(samples: samples, logs: redactedLogs)

        let manifest = DiagnosticsBundle(
            bundleId: bundleId,
            generatedAtRFC3339: timestamp,
            sampleCount: samples.count,
            logFilesIncluded: Array(redactedLogs.keys).sorted(),
            totalSizeBytes: totalSize,
            redactionApplied: true
        )

        try await writeArchive(manifest: manifest, samples: samples, logs: redactedLogs, to: destination)
        return manifest
    }

    // MARK: Private

    private func ensureDirectory() throws(ExportError) {
        do {
            try FileManager.default.createDirectory(
                at: exportDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw .destinationUnavailable(error.localizedDescription)
        }
    }

    private func calculateSize(samples: [SelfMetricSample], logs: [String: String]) -> Int {
        let sampleSize = samples.count * 256  // estimated bytes per sample
        let logSize = logs.values.reduce(0) { $0 + $1.utf8.count }
        return sampleSize + logSize
    }

    private func writeArchive(
        manifest: DiagnosticsBundle,
        samples: [SelfMetricSample],
        logs: [String: String],
        to destination: URL
    ) async throws(ExportError) {
        // Production implementation will use ZIPFoundation or equivalent.
        // This stub validates the pipeline without the archive dependency.
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(to: destination)
        } catch {
            throw .archiveFailed(error.localizedDescription)
        }
    }
}

// MARK: - LogRedactor protocol

/// Port for the log-redaction step in `DiagnosticsBundleExporter`.
///
/// Returns `nil` when redaction cannot be performed safely — causing the exporter to abort.
public protocol LogRedactor: Sendable {
    func redact(_ content: String) async -> String?
}

// MARK: - PassthroughLogRedactor (test double)

/// No-op redactor for use in unit tests. Returns content unchanged.
public struct PassthroughLogRedactor: LogRedactor, Sendable {
    public init() {}
    public func redact(_ content: String) async -> String? { content }
}
