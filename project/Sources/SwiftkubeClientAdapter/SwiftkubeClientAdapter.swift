// SwiftkubeClientAdapter.swift — infrastructure adapter placeholder
// Implements: KubernetesClientPort from ClusterConnectivity
// Library: swiftkube/client@0.17+ (Tier A per ADR-0019)
//          async-http-client@1.21+ (Tier A per ADR-0019) — used directly
//          for SSA PATCH (ADR-0019 §lines 184-186, server-side apply).
// Status: skeleton; port implementations pending domain ports definition.
import SwiftkubeClient
import AsyncHTTPClient
import ClusterConnectivity
import Foundation

/// Namespace marker for the SwiftkubeClientAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum SwiftkubeClientAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}
