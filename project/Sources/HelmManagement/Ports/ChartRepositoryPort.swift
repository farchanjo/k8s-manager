// Ports/ChartRepositoryPort.swift — helm_management bounded context
// DDD role: Port (outbound — Phase 2 OCI/HTTP chart fetch, declared but unimplemented)
// ADR ref: ADR-0015 §Phase 2 (OCI chart pull via apple/swift-container-plugin)
//
// Phase 1: this port is declared so the dependency injection registry is
// wired and the build is clean. No live adapter exists until Phase 2.

import Foundation
import SharedKernel

// MARK: - ChartRepositoryPort

/// Fetches Helm chart archives from OCI registries and HTTP chart repositories.
///
/// **Phase 2 port — declared but not yet implemented.** All methods throw
/// `ChartRepositoryError.notImplementedPhase2` in Phase 1.
///
/// Phase 2 implementation notes per ADR-0015:
/// - OCI pull uses `apple/swift-container-plugin` with media type
///   `application/vnd.cncf.helm.chart.content.v1.tar+gzip`.
/// - HTTP repos parse `index.yaml` from the repository base URL.
/// - Credentials are stored in the macOS Keychain via `local_persistence`.
public protocol ChartRepositoryPort: Sendable {
    /// Fetches `ChartMetadata` for a specific chart version from an OCI registry.
    ///
    /// - Parameters:
    ///   - reference: OCI reference string.
    ///     Example: `"oci://registry.example.com/charts/nginx:1.2.3"`.
    ///   - clusterId: Stable identifier for credential resolution.
    /// - Returns: The decoded `ChartMetadata` for the resolved chart version.
    /// - Throws: `ChartRepositoryError.notImplementedPhase2` in Phase 1.
    func fetchChartMetadataOCI(
        reference: String,
        clusterId: ClusterId
    ) async throws -> ChartMetadata

    /// Fetches `ChartMetadata` for a specific chart version from an HTTP
    /// chart repository.
    ///
    /// - Parameters:
    ///   - repositoryURL: Base URL of the chart repository.
    ///     Example: `"https://charts.example.com"`.
    ///   - chartName: Chart name as it appears in the repository index.
    ///   - version: Exact SemVer version string to fetch.
    ///   - clusterId: Stable identifier for credential resolution.
    /// - Returns: The decoded `ChartMetadata` for the specified version.
    /// - Throws: `ChartRepositoryError.notImplementedPhase2` in Phase 1.
    func fetchChartMetadataHTTP(
        repositoryURL: String,
        chartName: String,
        version: String,
        clusterId: ClusterId
    ) async throws -> ChartMetadata
}

// MARK: - ChartRepositoryError

/// Errors raised by `ChartRepositoryPort` implementations.
public enum ChartRepositoryError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented

    /// Phase 2 OCI and HTTP chart fetch is not yet implemented.
    /// Always thrown by the Phase 1 unimplemented sentinel.
    case notImplementedPhase2

    /// OCI registry or HTTP server could not be reached.
    case transportError(detail: String)

    /// The requested chart version does not exist in the repository.
    case notFound(chartName: String, version: String)

    /// The chart archive failed integrity or signature verification.
    case verificationFailed(detail: String)
}

// MARK: - UnimplementedChartRepositoryPort

/// Phase 1 sentinel. Throws `notImplementedPhase2` for all methods.
/// Replaced by a live OCI adapter in Phase 2.
public struct UnimplementedChartRepositoryPort: ChartRepositoryPort {
    public init() {}

    public func fetchChartMetadataOCI(
        reference: String,
        clusterId: ClusterId
    ) async throws -> ChartMetadata {
        throw ChartRepositoryError.notImplementedPhase2
    }

    public func fetchChartMetadataHTTP(
        repositoryURL: String,
        chartName: String,
        version: String,
        clusterId: ClusterId
    ) async throws -> ChartMetadata {
        throw ChartRepositoryError.notImplementedPhase2
    }
}
