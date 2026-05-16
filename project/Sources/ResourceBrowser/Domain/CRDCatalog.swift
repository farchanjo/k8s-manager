// Domain/CRDCatalog.swift — resource_browser bounded context
// DDD role: ValueObject — CRD catalog snapshot
// ADR ref: ADR-0052 (custom resource discovery and rendering)

import Foundation
import SharedKernel

// MARK: - PrinterColumn

/// A single `additionalPrinterColumn` entry from a CRD spec version.
///
/// Maps to the columns rendered in `kubectl get` output and used by
/// `CustomResourceListView` to build a dynamic table.
public struct PrinterColumn: Sendable, Hashable, Codable {

    /// Column header label (e.g. `"Ready"`, `"Age"`).
    public let name: String

    /// JSONPath expression into the custom resource object (e.g. `".status.ready"`).
    public let jsonPath: String

    /// Kubernetes printer-column type: `"string"`, `"integer"`, `"date"`, etc.
    public let type: String

    /// Memberwise initialiser.
    public init(name: String, jsonPath: String, type: String) {
        self.name = name
        self.jsonPath = jsonPath
        self.type = type
    }
}

// MARK: - CRDEntry

/// Immutable descriptor for a single Custom Resource Definition kind.
///
/// Built from the storage version of the CRD spec. Identifiable by its
/// `GroupVersionResource` so the sidebar and tab system can refer to it
/// without loading the full catalog.
public struct CRDEntry: Sendable, Hashable, Identifiable {

    /// Primary key — the plural GVR endpoint for this CRD.
    public let id: GroupVersionResource

    /// Human-readable display name derived from `spec.names.kind`.
    public let displayName: String

    /// `true` when instances are scoped to a Kubernetes namespace.
    public let isNamespaced: Bool

    /// Printer columns from `spec.versions[storage=true].additionalPrinterColumns`.
    ///
    /// Empty when the CRD declares no additional columns; the view falls back
    /// to Name / Namespace / Age.
    public let columns: [PrinterColumn]

    /// Kubernetes API category labels (e.g. `["all", "knative"]`).
    public let categories: [String]

    /// Memberwise initialiser.
    public init(
        id: GroupVersionResource,
        displayName: String,
        isNamespaced: Bool,
        columns: [PrinterColumn],
        categories: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.isNamespaced = isNamespaced
        self.columns = columns
        self.categories = categories
    }
}

// MARK: - CRDCatalog

/// Immutable snapshot of all CustomResourceDefinitions visible in a cluster.
///
/// Emitted by `CRDDiscoveryPort.discoverCRDs(clusterId:)` and by each
/// watch event from `CRDDiscoveryPort.watchCRDChanges(clusterId:)`.
public struct CRDCatalog: Sendable, Hashable {

    /// All CRD entries in this snapshot, in stable alphabetical order.
    public let entries: [CRDEntry]

    /// ISO 8601 / RFC 3339 timestamp when this snapshot was built.
    public let lastUpdatedRFC3339: String

    /// Memberwise initialiser.
    public init(entries: [CRDEntry], lastUpdatedRFC3339: String) {
        self.entries = entries
        self.lastUpdatedRFC3339 = lastUpdatedRFC3339
    }

    /// Groups entries by API group, returning a sorted dictionary.
    ///
    /// - Returns: A dictionary whose keys are API group strings (e.g.
    ///   `"argoproj.io"`) and whose values are the entries in that group,
    ///   sorted by `displayName`.
    public func groupedByAPIGroup() -> [String: [CRDEntry]] {
        var result: [String: [CRDEntry]] = [:]
        for entry in entries {
            let group = entry.id.group
            result[group, default: []].append(entry)
        }
        return result.mapValues { $0.sorted { $0.displayName < $1.displayName } }
    }
}
