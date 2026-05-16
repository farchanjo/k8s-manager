// Ports/MCPInvocationLogPort.swift — cluster_intelligence bounded context
// DDD role: Port (outbound — persistence of invocation audit log)
// ADR ref: ADR-0010 §Local persistence stores the MCP wire log
// Narrative ref: domain/narrative.md §Read models exposed to other contexts

import Foundation
import SharedKernel

// MARK: - MCPInvocationLogPort

/// Persists and retrieves `MCPInvocation` audit-log entries.
///
/// Declared in the domain core; implemented by `GRDBPersistenceAdapter`.
/// The domain core never imports GRDB or any SQLite bindings.
///
/// Invariant: log entries MUST NOT include bearer tokens, client
/// certificates, kubeconfig paths, or label values matching the
/// substring `secret` (case-insensitive). Enforcement is the responsibility
/// of the caller before calling `append(_:)`.
public protocol MCPInvocationLogPort: Sendable {
    /// Persists a completed invocation entry.
    ///
    /// - Parameter invocation: The invocation to store.
    /// - Throws: `MCPInvocationLogError` on persistence failure.
    func append(_ invocation: MCPInvocation) async throws

    /// Retrieves the most recent `limit` invocations in descending
    /// chronological order.
    ///
    /// - Parameter limit: Maximum number of entries to return.
    /// - Returns: An `MCPInvocationLogReadModel` with up to `limit` entries.
    /// - Throws: `MCPInvocationLogError` on read failure.
    func recent(limit: Int) async throws -> MCPInvocationLogReadModel
}

// MARK: - MCPInvocationLogError

/// Errors raised by `MCPInvocationLogPort` implementations.
public enum MCPInvocationLogError: Error, Sendable {
    /// A port that has not been registered in this process.
    case unimplemented
    /// A write to the underlying store failed.
    case writeFailed(detail: String)
    /// A read from the underlying store failed.
    case readFailed(detail: String)
}

// MARK: - UnimplementedMCPInvocationLogPort

/// Crash-fast sentinel used before an adapter registers a real implementation.
public struct UnimplementedMCPInvocationLogPort: MCPInvocationLogPort {
    public init() {}

    public func append(_ invocation: MCPInvocation) async throws {
        throw MCPInvocationLogError.unimplemented
    }

    public func recent(limit: Int) async throws -> MCPInvocationLogReadModel {
        throw MCPInvocationLogError.unimplemented
    }
}
