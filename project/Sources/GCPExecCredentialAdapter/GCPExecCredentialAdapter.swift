// GCPExecCredentialAdapter.swift — infrastructure adapter placeholder
// Implements: ExecCredentialPort from ClusterConnectivity (GKE / Workload Identity)
// Library: vapor/jwt-kit + apple/swift-crypto + apple/_CryptoExtras (Tier A per ADR-0019)
// Status: skeleton; port implementations pending domain ports definition.
import JWTKit
import Crypto
import _CryptoExtras
import ClusterConnectivity
import Foundation

/// Namespace marker for the GCPExecCredentialAdapter adapter target.
///
/// Concrete actor types implementing the domain ports land under this enum
/// in subsequent rounds. This file exists so the target compiles cleanly
/// under Swift 6 strict concurrency with the imported infrastructure library.
public enum GCPExecCredentialAdapter: Sendable {
    public static let moduleVersion = "0.0.1-skeleton"
}
