// ClusterConnectivity.swift — cluster_connectivity domain core
// Bounded context: cluster_connectivity (per ADR-0005)

/// Namespace marker for the ClusterConnectivity bounded context.
///
/// Domain types live in `Domain/`, hexagonal port protocols in `Ports/`,
/// and the per-cluster actor in `Actors/`.
public enum ClusterConnectivity: Sendable {
    /// Build identifier — bumped manually until CI emits this.
    public static let moduleVersion = "0.1.0"
}
