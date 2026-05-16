// Domain/ResourceListExporter.swift — app_shell bounded context
// DDD role: ApplicationService — CSV and YAML export for resource list rows
// ADR ref: ADR-0060 (resource list export CSV and YAML)

import Foundation

// MARK: - ResourceListRow

/// Generic row snapshot supplied to `ListExportService` by any list view-model.
///
/// Each view-model maps its typed row struct to `ResourceListRow` at export time,
/// producing only the columns defined in the ADR-0060 `KindExportConfig` for the kind.
public struct ResourceListRow: Sendable {
    /// Ordered column values matching the `KindExportConfig` column list.
    /// Multi-value fields (e.g. conditions) use semicolons as internal separator.
    public let values: [String]

    public init(values: [String]) {
        self.values = values
    }
}

// MARK: - KindExportConfig

/// Ordered column subset for a given Kubernetes kind family per ADR-0060.
///
/// Column names use lowercase-hyphenated identifiers. The order determines the
/// CSV header row and the order of `ResourceListRow.values`.
public struct KindExportConfig: Sendable {
    /// Kubernetes kind string (e.g. `"Pod"`, `"Deployment"`).
    public let kind: String
    /// Ordered column name list, max 12 per spec.
    public let columns: [String]

    public init(kind: String, columns: [String]) {
        self.kind = kind
        self.columns = columns
    }

    // MARK: Static catalogue

    /// Returns the canonical `KindExportConfig` for the given kind, or a minimal
    /// default (`name`, `status`, `age`) when the kind is not in the catalogue.
    public static func config(forKind kind: String) -> KindExportConfig {
        catalogue[kind] ?? defaultConfig(kind: kind)
    }

    private static func defaultConfig(kind: String) -> KindExportConfig {
        KindExportConfig(kind: kind, columns: ["name", "status", "age"])
    }

    // MARK: Catalogue (ADR-0060 column subsets)

    private static let catalogue: [String: KindExportConfig] = {
        var c: [String: KindExportConfig] = [:]
        c["Node"] = .init(kind: "Node", columns: [
            "name", "kubernetes-version", "age", "roles", "conditions", "internal-ip",
        ])
        c["Pod"] = .init(kind: "Pod", columns: [
            "name", "namespace", "status", "ready", "restarts", "node", "age",
        ])
        for k in ["Deployment", "StatefulSet", "DaemonSet", "ReplicaSet"] {
            c[k] = .init(kind: k, columns: [
                "name", "namespace", "ready", "up-to-date", "available", "age",
            ])
        }
        for k in ["Job", "CronJob"] {
            c[k] = .init(kind: k, columns: [
                "name", "namespace", "completions", "duration", "age",
            ])
        }
        c["ConfigMap"] = .init(kind: "ConfigMap", columns: [
            "name", "namespace", "keys", "age",
        ])
        c["Secret"] = .init(kind: "Secret", columns: [
            "name", "namespace", "type", "keys", "age",
        ])
        c["Service"] = .init(kind: "Service", columns: [
            "name", "namespace", "type", "cluster-ip", "external-ip", "ports", "age",
        ])
        c["Ingress"] = .init(kind: "Ingress", columns: [
            "name", "namespace", "class", "hosts", "address", "ports", "age",
        ])
        c["PersistentVolume"] = .init(kind: "PersistentVolume", columns: [
            "name", "capacity", "access-modes", "reclaim-policy",
            "status", "claim", "storage-class", "age",
        ])
        c["PersistentVolumeClaim"] = .init(kind: "PersistentVolumeClaim", columns: [
            "name", "namespace", "status", "volume", "capacity",
            "access-modes", "storage-class", "age",
        ])
        for k in ["Namespace", "Event"] {
            c[k] = .init(kind: k, columns: ["name", "status", "age"])
        }
        for k in ["Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding"] {
            c[k] = .init(kind: k, columns: ["name", "namespace", "age"])
        }
        return c
    }()
}

// MARK: - CSVExportError

/// Errors produced by `ListExportService`.
public enum CSVExportError: Error, Sendable {
    /// Row value count does not match the column count defined by `KindExportConfig`.
    case columnCountMismatch(expected: Int, got: Int, rowIndex: Int)
}

// MARK: - ListExportService

/// ApplicationService that serialises a filtered row list to RFC 4180 CSV bytes.
///
/// - Encoding: UTF-8 (optional BOM).
/// - Delimiter: comma.
/// - Line endings: CRLF per RFC 4180.
/// - Header row: always present; column names from `KindExportConfig`.
/// - Multi-value fields: already semicolon-joined in `ResourceListRow.values`.
/// - Quoting: RFC 4180 — fields with commas, double-quotes, or newlines are
///   enclosed in double-quotes; embedded double-quotes doubled.
public struct ListExportService: Sendable {

    public init() {}

    /// Serialises the row list to RFC 4180 CSV bytes.
    ///
    /// - Parameters:
    ///   - rows: Already-filtered, sorted rows from the view model.
    ///   - config: Column subset configuration for the current kind.
    ///   - addBOM: Prepend UTF-8 BOM (`EF BB BF`) for Excel compatibility.
    ///   - refreshTimestamp: ISO 8601 string embedded in a header comment for staleness transparency.
    /// - Returns: UTF-8 encoded CSV data.
    /// - Throws: `CSVExportError.columnCountMismatch` when a row has the wrong column count.
    public func csvData(
        from rows: [ResourceListRow],
        config: KindExportConfig,
        addBOM: Bool = false,
        refreshTimestamp: String = ""
    ) throws -> Data {
        var lines: [String] = []
        if !refreshTimestamp.isEmpty {
            lines.append("# Last refreshed \(refreshTimestamp)")
        }
        lines.append(csvRow(values: config.columns))
        for (index, row) in rows.enumerated() {
            guard row.values.count == config.columns.count else {
                throw CSVExportError.columnCountMismatch(
                    expected: config.columns.count,
                    got: row.values.count,
                    rowIndex: index
                )
            }
            lines.append(csvRow(values: row.values))
        }
        let body = lines.joined(separator: "\r\n") + "\r\n"
        var bytes = body.data(using: .utf8) ?? Data()
        if addBOM {
            bytes.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: bytes.startIndex)
        }
        return bytes
    }

    // MARK: Private

    /// Encodes a single row of values as a comma-delimited RFC 4180 string.
    private func csvRow(values: [String]) -> String {
        values.map(quoteField).joined(separator: ",")
    }

    /// Quotes a single field per RFC 4180 rules.
    private func quoteField(_ value: String) -> String {
        let needsQuote = value.contains(",") || value.contains("\"") || value.contains("\n")
        if !needsQuote { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

// MARK: - CSVFilenameTemplate

/// Pure function producing the ADR-0060-compliant filename for a CSV list export.
///
/// Pattern: `<Kind>-<ClusterDisplayName>-<YYYY-MM-DDTHH-MM-SSZ>.csv`
/// Spaces in `clusterDisplayName` are replaced with hyphens; non-ASCII characters
/// are percent-encoded.
public enum CSVFilenameTemplate {

    /// Generates the suggested CSV filename.
    ///
    /// - Parameters:
    ///   - kind: Kubernetes kind string.
    ///   - clusterDisplayName: Human-readable cluster name from `ClusterStripPin`.
    ///   - date: Export timestamp (defaults to `Date.now`).
    public static func filename(
        kind: String,
        clusterDisplayName: String,
        date: Date = .now
    ) -> String {
        let safeName = sanitise(clusterDisplayName)
        let ts = isoTimestamp(from: date)
        return "\(kind)-\(safeName)-\(ts).csv"
    }

    /// Generates the suggested YAML filename for a namespace-scoped resource.
    public static func yamlFilename(
        kind: String,
        namespace: String,
        name: String,
        date: Date = .now
    ) -> String {
        let ts = isoTimestamp(from: date)
        return "\(kind)-\(namespace)-\(name)-\(ts).yaml"
    }

    /// Generates the suggested YAML filename for a cluster-scoped resource.
    public static func yamlFilenameClusterScoped(
        kind: String,
        name: String,
        date: Date = .now
    ) -> String {
        let ts = isoTimestamp(from: date)
        return "\(kind)-\(name)-\(ts).yaml"
    }

    // MARK: Private

    private static func sanitise(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: " ", with: "-")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? raw
    }

    private static func isoTimestamp(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        return f.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}
