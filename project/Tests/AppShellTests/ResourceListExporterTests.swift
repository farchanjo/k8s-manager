// Tests/AppShellTests/ResourceListExporterTests.swift
// Coverage: ListExportService CSV serialisation + KindExportConfig catalogue
// + CSVFilenameTemplate per ADR-0060.

import XCTest
@testable import AppShell

// MARK: - ListExportServiceCSVTests

final class ListExportServiceCSVTests: XCTestCase {

    private let service = ListExportService()
    private let podConfig = KindExportConfig.config(forKind: "Pod")

    // MARK: Header row

    func test_headerRow_matchesColumns() throws {
        let data = try service.csvData(from: [], config: podConfig)
        let text = String(data: data, encoding: .utf8)!
        let firstLine = text.components(separatedBy: "\r\n")[0]
        XCTAssertEqual(firstLine, "name,namespace,status,ready,restarts,node,age")
    }

    // MARK: CRLF line endings

    func test_lineEndings_areCRLF() throws {
        let row = ResourceListRow(values: ["pod-1", "default", "Running", "1/1", "0", "node-1", "5d"])
        let data = try service.csvData(from: [row], config: podConfig)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\r\n"), "Output must use CRLF line endings (RFC 4180)")
    }

    // MARK: Quoting

    func test_fieldWithComma_isQuoted() throws {
        let row = ResourceListRow(values: [
            "pod-1", "default", "Running", "1/1", "0", "node-a,node-b", "5d",
        ])
        let data = try service.csvData(from: [row], config: podConfig)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\"node-a,node-b\""), "Comma in field must be quoted")
    }

    func test_fieldWithDoubleQuote_isEscaped() throws {
        let row = ResourceListRow(values: [
            "pod-1", "default", "Running", "1/1", "0", "node\"special", "5d",
        ])
        let data = try service.csvData(from: [row], config: podConfig)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.contains("\"node\"\"special\""), "Embedded double-quote must be escaped as \"\"")
    }

    func test_plainField_isNotQuoted() throws {
        let row = ResourceListRow(values: ["my-pod", "default", "Running", "1/1", "0", "node-1", "1d"])
        let data = try service.csvData(from: [row], config: podConfig)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains("\"my-pod\""), "Plain field must not be unnecessarily quoted")
    }

    // MARK: BOM

    func test_bomFlag_prepends_EFBBBF() throws {
        let data = try service.csvData(from: [], config: podConfig, addBOM: true)
        let bomBytes: [UInt8] = [0xEF, 0xBB, 0xBF]
        XCTAssertTrue(data.prefix(3).elementsEqual(bomBytes), "BOM must be the first three bytes")
    }

    func test_noBomFlag_doesNotPrependBOM() throws {
        let data = try service.csvData(from: [], config: podConfig, addBOM: false)
        let firstBytes: [UInt8] = Array(data.prefix(3))
        XCTAssertNotEqual(firstBytes, [0xEF, 0xBB, 0xBF])
    }

    // MARK: Row count

    func test_rowCount_matchesInput() throws {
        let rows = (0..<5).map { i in
            ResourceListRow(values: ["pod-\(i)", "default", "Running", "1/1", "0", "node-1", "1d"])
        }
        let data = try service.csvData(from: rows, config: podConfig)
        let text = String(data: data, encoding: .utf8)!
        let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty && !$0.hasPrefix("#") }
        // header + 5 data rows
        XCTAssertEqual(lines.count, 6)
    }

    // MARK: Error: column count mismatch

    func test_columnCountMismatch_throws() {
        let badRow = ResourceListRow(values: ["only-one-value"])
        XCTAssertThrowsError(try service.csvData(from: [badRow], config: podConfig)) { error in
            guard case CSVExportError.columnCountMismatch(let expected, let got, let index) = error else {
                return XCTFail("Expected CSVExportError.columnCountMismatch")
            }
            XCTAssertEqual(expected, podConfig.columns.count)
            XCTAssertEqual(got, 1)
            XCTAssertEqual(index, 0)
        }
    }

    // MARK: Refresh timestamp comment

    func test_refreshTimestamp_appearsAsComment() throws {
        let ts = "2026-05-16T14:00:00Z"
        let data = try service.csvData(from: [], config: podConfig, refreshTimestamp: ts)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("# Last refreshed \(ts)"), "Timestamp comment must be first line")
    }
}

// MARK: - KindExportConfigTests

final class KindExportConfigTests: XCTestCase {

    func test_pod_hasSevenColumns() {
        let config = KindExportConfig.config(forKind: "Pod")
        XCTAssertEqual(config.columns.count, 7)
        XCTAssertEqual(config.columns.first, "name")
    }

    func test_node_hasSixColumns() {
        let config = KindExportConfig.config(forKind: "Node")
        XCTAssertEqual(config.columns.count, 6)
    }

    func test_deployment_hasSixColumns() {
        let config = KindExportConfig.config(forKind: "Deployment")
        XCTAssertEqual(config.columns.count, 6)
    }

    func test_secret_hasSecretSpecificColumns() {
        let config = KindExportConfig.config(forKind: "Secret")
        XCTAssertTrue(config.columns.contains("type"))
        XCTAssertTrue(config.columns.contains("keys"))
        XCTAssertFalse(config.columns.contains("data"),
                       "Secret data values must never appear in the column config")
    }

    func test_unknownKind_returnsDefaultThreeColumns() {
        let config = KindExportConfig.config(forKind: "MyCustomKind")
        XCTAssertEqual(config.columns, ["name", "status", "age"])
    }

    func test_allCataloguedKinds_haveAtLeastThreeColumns() {
        let kinds = ["Node", "Pod", "Deployment", "StatefulSet", "DaemonSet", "ReplicaSet",
                     "Job", "CronJob", "ConfigMap", "Secret", "Service", "Ingress",
                     "PersistentVolume", "PersistentVolumeClaim", "Namespace", "Event",
                     "Role", "ClusterRole", "RoleBinding", "ClusterRoleBinding"]
        for kind in kinds {
            let config = KindExportConfig.config(forKind: kind)
            XCTAssertGreaterThanOrEqual(config.columns.count, 3, "kind=\(kind) must have >= 3 columns")
        }
    }

    func test_noKind_exceeds12Columns() {
        let kinds = ["Node", "Pod", "Deployment", "Service", "Ingress",
                     "PersistentVolume", "PersistentVolumeClaim"]
        for kind in kinds {
            let config = KindExportConfig.config(forKind: kind)
            XCTAssertLessThanOrEqual(config.columns.count, 12,
                                     "kind=\(kind) must not exceed 12 columns per ADR-0060")
        }
    }
}

// MARK: - CSVFilenameTemplateTests

final class CSVFilenameTemplateTests: XCTestCase {

    private static let referenceDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 16
        c.hour = 14;   c.minute = 32; c.second = 7
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    func test_csvFilename_containsKindAndCluster() {
        let name = CSVFilenameTemplate.filename(
            kind: "Pod",
            clusterDisplayName: "prod-aks",
            date: Self.referenceDate
        )
        XCTAssertTrue(name.hasPrefix("Pod-prod-aks-"))
        XCTAssertTrue(name.hasSuffix(".csv"))
    }

    func test_csvFilename_spacesInClusterNameReplacedWithHyphens() {
        let name = CSVFilenameTemplate.filename(
            kind: "Pod",
            clusterDisplayName: "my cluster",
            date: Self.referenceDate
        )
        XCTAssertFalse(name.contains(" "), "Spaces must be replaced with hyphens")
    }

    func test_csvFilename_colonReplacedInTimestamp() {
        let name = CSVFilenameTemplate.filename(
            kind: "Pod",
            clusterDisplayName: "c",
            date: Self.referenceDate
        )
        XCTAssertFalse(name.contains(":"), "Colons must not appear in filename")
    }

    func test_yamlFilename_namespacedFormat() {
        let name = CSVFilenameTemplate.yamlFilename(
            kind: "Deployment",
            namespace: "default",
            name: "my-api",
            date: Self.referenceDate
        )
        XCTAssertTrue(name.hasPrefix("Deployment-default-my-api-"))
        XCTAssertTrue(name.hasSuffix(".yaml"))
    }

    func test_yamlFilenameClusterScoped_omitsNamespace() {
        let name = CSVFilenameTemplate.yamlFilenameClusterScoped(
            kind: "Node",
            name: "worker-01",
            date: Self.referenceDate
        )
        XCTAssertTrue(name.hasPrefix("Node-worker-01-"))
        XCTAssertTrue(name.hasSuffix(".yaml"))
        XCTAssertFalse(name.contains("nil"))
    }
}
