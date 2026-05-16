// Ports/HelmReleaseStorePort.swift — helm_management bounded context
// DDD role: Port (outbound — reads/writes Kubernetes Secrets for Helm releases)
// ADR ref: ADR-0015 §Phase 1 §Secret decoding

import Foundation
import SharedKernel

// MARK: - HelmReleaseStorePort

/// Reads and writes `helm.sh/release.v1` Kubernetes Secrets, materialising
/// `Release` aggregates through base64 → gunzip → JSON decode pipeline.
///
/// Declared in the domain core; implemented by infrastructure adapters (e.g.
/// `SwiftkubeClientAdapter`). The domain core never imports `AsyncHTTPClient`,
/// `SwiftkubeClient`, or `Compression`.
///
/// Decoding procedure per ADR-0015 §Secret decoding:
/// 1. Base64-decode `data["release"]` using Foundation.
/// 2. Gunzip the decoded bytes (Foundation Compression or SWCompression).
/// 3. JSON-decode the resulting bytes into a `HelmReleasePayload` struct.
/// 4. Evaluate the `release_decoder_invariants` Rego policy.
/// 5. Construct a `Release` aggregate.
public protocol HelmReleaseStorePort: Sendable {
    /// Lists all `helm.sh/release.v1` Secrets in `namespace` using the label
    /// selector `owner=helm`, decodes each payload, and returns the resulting
    /// `Release` aggregates in unspecified order.
    ///
    /// - Parameters:
    ///   - clusterId: Stable identifier of the active cluster context.
    ///   - namespace: Kubernetes namespace to search. Pass `nil` to list across
    ///     all namespaces visible to the operator's credentials.
    /// - Returns: All decodable release revisions found. Secrets that fail the
    ///   invariants policy are surfaced as `HelmReleaseStoreError.decodeError`
    ///   entries and never returned as partial aggregates.
    /// - Throws: `HelmReleaseStoreError` on transport or decode failure.
    func listReleases(
        clusterId: ClusterId,
        namespace: String?
    ) async throws -> [Release]

    /// Reads a single `helm.sh/release.v1` Secret by its canonical name and
    /// returns the decoded `Release` aggregate.
    ///
    /// - Parameters:
    ///   - secretName: The Kubernetes Secret name.
    ///     Convention: `sh.helm.release.v1.<name>.v<version>`.
    ///   - namespace: Kubernetes namespace of the Secret.
    ///   - clusterId: Stable identifier of the active cluster context.
    /// - Returns: The decoded `Release` aggregate.
    /// - Throws: `HelmReleaseStoreError.notFound` when absent,
    ///   `HelmReleaseStoreError.decodeError` on policy failure.
    func readRelease(
        secretName: String,
        namespace: String,
        clusterId: ClusterId
    ) async throws -> Release

    /// Writes a new revision Secret for a rollback operation.
    ///
    /// Creates a `helm.sh/release.v1` Secret encoding the provided `Release`
    /// aggregate. The Secret name follows the convention:
    /// `sh.helm.release.v1.<name>.v<version>`. Called by
    /// `RollbackOrchestrator` after lease acquisition.
    ///
    /// - Parameters:
    ///   - release: The new revision aggregate to persist.
    ///   - clusterId: Stable identifier of the active cluster context.
    /// - Throws: `HelmReleaseStoreError` on write failure.
    func writeRelease(
        _ release: Release,
        clusterId: ClusterId
    ) async throws
}

// MARK: - HelmReleaseStoreError

/// Errors raised by `HelmReleaseStorePort` implementations.
public enum HelmReleaseStoreError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// Network or TLS failure before a response was received.
    case transportError(detail: String)

    /// The Secret could not be found in the cluster.
    case notFound(secretName: String, namespace: String)

    /// The Secret payload failed the base64-decode, gunzip, or JSON-decode step.
    case decodeError(secretName: String, detail: String)

    /// The decoded payload failed the `release_decoder_invariants` Rego policy.
    case invariantViolation(secretName: String, violations: [String])

    /// The cluster returned an unexpected HTTP status.
    case unexpectedStatus(code: Int, detail: String)
}

// MARK: - UnimplementedHelmReleaseStorePort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedHelmReleaseStorePort: HelmReleaseStorePort {
    public init() {}

    public func listReleases(
        clusterId: ClusterId,
        namespace: String?
    ) async throws -> [Release] {
        throw HelmReleaseStoreError.unimplemented
    }

    public func readRelease(
        secretName: String,
        namespace: String,
        clusterId: ClusterId
    ) async throws -> Release {
        throw HelmReleaseStoreError.unimplemented
    }

    public func writeRelease(
        _ release: Release,
        clusterId: ClusterId
    ) async throws {
        throw HelmReleaseStoreError.unimplemented
    }
}
