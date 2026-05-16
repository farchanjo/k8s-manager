// Ports/ReleaseDecoderPort.swift — helm_management bounded context
// DDD role: Port (inbound on domain side — decodes Helm Secret payload into Release aggregate)
// ADR ref: ADR-0015 §Phase 1 §Secret decoding

import Foundation
import SharedKernel

// MARK: - ReleaseDecoderPort

/// Decodes the raw `data["release"]` payload from a `helm.sh/release.v1`
/// Kubernetes Secret into a `Release` aggregate.
///
/// The decoding pipeline per ADR-0015 §Secret decoding:
/// 1. Base64-decode the `secretData` bytes using Foundation.
/// 2. Gunzip the decoded bytes (Foundation Compression or SWCompression).
/// 3. JSON-decode the resulting bytes into the `HelmReleasePayload` struct.
/// 4. Evaluate the `release_decoder_invariants` Rego policy.
/// 5. Construct and return a `Release` aggregate.
///
/// The domain core never imports infrastructure modules (`AsyncHTTPClient`,
/// `SwiftkubeClient`, `Compression`). All infrastructure access is mediated
/// through this port; the live implementation lives in the infrastructure layer
/// (`HelmSecretDecoderAdapter`).
public protocol ReleaseDecoderPort: Sendable {
    /// Decodes a raw Helm Secret payload into a `Release` aggregate.
    ///
    /// - Parameter secretData: The raw value of `data["release"]` from a
    ///   `helm.sh/release.v1` Kubernetes Secret. This is the base64-encoded,
    ///   gzip-compressed JSON representation of the Helm release payload.
    ///   The caller must not pre-decode; the adapter owns the full pipeline.
    /// - Returns: A fully-materialised `Release` aggregate.
    /// - Throws: `ReleaseDecoderError` when any step of the pipeline fails or
    ///   when the Rego invariants policy is violated.
    func decode(secretData: Data) throws -> Release
}

// MARK: - ReleaseDecoderError

/// Errors raised by `ReleaseDecoderPort` implementations.
public enum ReleaseDecoderError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// The `secretData` bytes are not valid base64.
    case base64DecodeFailed

    /// Gunzip decompression of the decoded bytes failed.
    case gunzipFailed(detail: String)

    /// JSON decoding of the decompressed bytes into `HelmReleasePayload` failed.
    case jsonDecodeFailed(detail: String)

    /// The decoded payload violated one or more `release_decoder_invariants` Rego rules.
    /// For example, the manifest contains PEM-encoded certificate blocks.
    case invariantViolation(violations: [String])
}

// MARK: - UnimplementedReleaseDecoderPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
///
/// Throws `ReleaseDecoderError.unimplemented` for all calls. Infrastructure
/// adapters replace this at composition root by overriding `liveValue`.
public struct UnimplementedReleaseDecoderPort: ReleaseDecoderPort {
    public init() {}

    public func decode(secretData: Data) throws -> Release {
        throw ReleaseDecoderError.unimplemented
    }
}
