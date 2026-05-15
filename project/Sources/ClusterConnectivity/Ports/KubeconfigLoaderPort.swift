// Ports/KubeconfigLoaderPort.swift — cluster_connectivity bounded context
// DDD role: Port (primary — inbound from infrastructure)
// Narrative ref: domain/narrative.md §Tactical roles

import Foundation
import SharedKernel

// MARK: - KubeconfigLoaderPort

/// Loads and parses a kubeconfig file from disk, returning the domain aggregate.
///
/// Declared in the domain core; implemented by `YamsKubeconfigAdapter` in
/// infrastructure. The domain core never imports Yams.
public protocol KubeconfigLoaderPort: Sendable {
    /// Reads and parses the kubeconfig at `path`, returning an immutable
    /// `Kubeconfig` aggregate.
    ///
    /// - Parameter path: Absolute, symlink-resolved path to the kubeconfig
    ///   file.
    /// - Throws: `KubeconfigLoadError` on parse failure or I/O error.
    func load(from path: KubeconfigPath) async throws -> Kubeconfig

    /// Returns the ordered list of context entries from a parsed `Kubeconfig`.
    func contexts(in config: Kubeconfig) -> [KubeconfigContext]

    /// Returns the context entry matching `config.currentContext`, or `nil`
    /// when `currentContext` is absent or unresolvable.
    func activeContext(in config: Kubeconfig) -> KubeconfigContext?
}

// MARK: - KubeconfigLoadError

/// Errors raised by `KubeconfigLoaderPort` implementations.
public enum KubeconfigLoadError: Error, Sendable {
    /// The file at the given path could not be read.
    case ioError(path: String, underlying: String)

    /// The YAML content could not be parsed into a valid kubeconfig structure.
    case parseError(detail: String)

    /// The kubeconfig did not satisfy the domain validation policy.
    case validationError(violations: [String])

    /// A port that has not been registered in this process.
    case unimplemented
}

// MARK: - UnimplementedKubeconfigLoaderPort

/// Crash-fast sentinel used as `liveValue` / `testValue` before an adapter
/// registers a real implementation.
public struct UnimplementedKubeconfigLoaderPort: KubeconfigLoaderPort {
    public init() {}

    public func load(from path: KubeconfigPath) async throws -> Kubeconfig {
        throw KubeconfigLoadError.unimplemented
    }

    public func contexts(in config: Kubeconfig) -> [KubeconfigContext] {
        config.contexts
    }

    public func activeContext(in config: Kubeconfig) -> KubeconfigContext? {
        guard let current = config.currentContext else { return nil }
        return config.contexts.first { $0.name == current }
    }
}
