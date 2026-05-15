// YamsKubeconfigAdapter.swift — infrastructure adapter placeholder
// Implements: KubeconfigPort from ClusterConnectivity
// Library: jpsim/Yams@5.1+ (Tier A per ADR-0019)
// Status: skeleton; port implementations pending domain ports definition.
import Yams
import ClusterConnectivity
import Foundation

/// Namespace marker for the YamsKubeconfigAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum YamsKubeconfigAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}
