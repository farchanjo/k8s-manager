// Views/Inspector/InspectorKey.swift — app_shell bounded context
// DDD role: Value object — inspector selection identity
// ADR ref: ADR-0073 (inspector trailing column substitutes resource detail tabs)

import Foundation
import SharedKernel

// MARK: - InspectorKey

/// Stable identity for a specific resource instance displayed in the Inspector.
///
/// Acts as the "address" passed from a resource list row to
/// `ResourceInspectorViewModel`. When `selectedKey` changes the view model
/// cancels any in-flight subscription and starts a fresh one.
///
/// Conforms to `Hashable` so the `@Observable` view model can detect changes
/// efficiently via `==` diffing, and to `Sendable` for safe crossing of
/// actor isolation boundaries from `@MainActor` list views.
///
/// ADR-0073 §"ResourceInspectorViewModel": keyed by
/// `(clusterId, resourceKind, resourceName, namespace?)`.
public struct InspectorKey: Hashable, Sendable {

    /// Cluster that owns this resource.
    public let clusterId: ClusterId

    /// Kubernetes kind name (e.g. `"Pod"`, `"Deployment"`).
    public let kind: String

    /// Resource name within its namespace (or cluster-wide for cluster-scoped resources).
    public let name: String

    /// Namespace, or `nil` for cluster-scoped resources.
    public let namespace: String?

    /// Designated initialiser.
    public init(
        clusterId: ClusterId,
        kind: String,
        name: String,
        namespace: String?
    ) {
        self.clusterId = clusterId
        self.kind = kind
        self.name = name
        self.namespace = namespace
    }
}
