// SharedKernel/FailureMode/FailureMode.swift — shared_kernel bounded context
// DDD role: ValueObject (catalogue entry)
// ADR ref: ADR-0041 (FailureMode catalogue §F1…F19+)

import Foundation

// MARK: - Supporting enums

/// Strategy the UI or orchestration layer should surface when a failure occurs.
public enum RecoveryStrategy: String, Sendable, Codable, Hashable, CaseIterable {
    /// Transient failure — retry the same operation automatically or on demand.
    case retry
    /// Credentials expired or invalid — prompt re-authentication.
    case reauth
    /// Stale UI state — reload the affected resource list or view.
    case reload
    /// Process-level failure — suggest a full application restart.
    case restart
    /// Operator intervention required — display guidance and stop.
    case manual
}

/// Operational severity classifying the impact radius of a failure.
public enum Severity: String, Sendable, Codable, Hashable, CaseIterable {
    /// Informational — no action needed; displayed for transparency only.
    case info
    /// Degraded functionality — operation can proceed with reduced capability.
    case warning
    /// Operation failed — user action likely needed.
    case error
    /// System integrity at risk — mandatory operator intervention.
    case critical
}

// MARK: - FailureMode

/// An immutable, catalogue-registered failure descriptor.
///
/// Each entry encodes a stable machine-readable ``code`` (e.g. ``"F11"``), a
/// short human-readable ``title``, a ``userMessage`` suitable for display in the
/// UI, a recommended ``recovery`` strategy, and a ``severity`` level.
///
/// Conforms to `Sendable`, `Codable`, and `Hashable` so entries can be stored,
/// transmitted across actor boundaries, and used as dictionary keys.
public struct FailureMode: Sendable, Codable, Hashable {
    /// Stable catalogue code (e.g. ``"F01"``). Never changes after publication.
    public let code: String

    /// Short human-readable label used in log messages and alerts.
    public let title: String

    /// User-facing prose — safe to show directly in SwiftUI alerts or banners.
    public let userMessage: String

    /// Recommended recovery action for the UI / orchestration layer.
    public let recovery: RecoveryStrategy

    /// Impact severity.
    public let severity: Severity

    /// Creates a failure-mode entry.
    public init(
        code: String,
        title: String,
        userMessage: String,
        recovery: RecoveryStrategy,
        severity: Severity
    ) {
        self.code = code
        self.title = title
        self.userMessage = userMessage
        self.recovery = recovery
        self.severity = severity
    }
}

// MARK: - FailureCatalogue

/// Static catalogue of well-known application failure modes (ADR-0041 §F1…F19+).
///
/// Callers look up entries by code via ``entry(for:)``. The catalogue is
/// intentionally exhaustive at the source-of-truth level; adapters that surface
/// domain-specific failures map to these entries at the anti-corruption layer.
public enum FailureCatalogue {

    // MARK: Catalogue

    /// All registered failure modes indexed by their stable ``code``.
    private static let catalogue: [String: FailureMode] = {
        let entries: [FailureMode] = [
            // F01 — network unreachable
            FailureMode(
                code: "F01",
                title: "Network Unreachable",
                userMessage: "The Kubernetes API server could not be reached. "
                    + "Check your network connection and kubeconfig server URL.",
                recovery: .retry,
                severity: .error
            ),

            // F02 — authentication expired
            FailureMode(
                code: "F02",
                title: "Authentication Expired",
                userMessage: "Your cluster credentials have expired. "
                    + "Re-authenticate via your identity provider to continue.",
                recovery: .reauth,
                severity: .error
            ),

            // F03 — watch gone (HTTP 410)
            FailureMode(
                code: "F03",
                title: "Watch Resource Version Gone",
                userMessage: "The server discarded the watch bookmark (HTTP 410). "
                    + "The resource list will be reloaded from scratch.",
                recovery: .reload,
                severity: .warning
            ),

            // F04 — mutation conflict (HTTP 409)
            FailureMode(
                code: "F04",
                title: "Resource Conflict",
                userMessage: "The resource was modified by another actor (HTTP 409). "
                    + "Reload the current state and re-apply your changes.",
                recovery: .reload,
                severity: .warning
            ),

            // F05 — audit chain tamper detected
            FailureMode(
                code: "F05",
                title: "Audit Chain Integrity Failure",
                userMessage: "The local audit log failed its integrity check. "
                    + "Manual review is required before operations can resume.",
                recovery: .manual,
                severity: .critical
            ),

            // F06 — kubeconfig parse error
            FailureMode(
                code: "F06",
                title: "Kubeconfig Parse Error",
                userMessage: "The kubeconfig file could not be parsed. "
                    + "Verify the YAML syntax and cluster/user/context sections.",
                recovery: .manual,
                severity: .error
            ),

            // F07 — LLM rate limit
            FailureMode(
                code: "F07",
                title: "LLM Rate Limit Exceeded",
                userMessage: "The LLM provider returned a rate-limit response (HTTP 429). "
                    + "Wait a moment and retry your request.",
                recovery: .retry,
                severity: .warning
            ),

            // F08 — prompt injection detected
            FailureMode(
                code: "F08",
                title: "Prompt Injection Detected",
                userMessage: "The assistant detected a potential prompt-injection pattern "
                    + "in the Kubernetes resource payload. The request was blocked.",
                recovery: .manual,
                severity: .critical
            ),

            // F09 — Helm release failure
            FailureMode(
                code: "F09",
                title: "Helm Release Failed",
                userMessage: "The Helm release operation failed. "
                    + "Check the release status and review the chart values.",
                recovery: .manual,
                severity: .error
            ),

            // F10 — port-forward bind conflict
            FailureMode(
                code: "F10",
                title: "Port Forward Bind Conflict",
                userMessage: "The requested local port is already in use. "
                    + "Choose a different local port or release the existing binding.",
                recovery: .manual,
                severity: .error
            ),

            // F11 — database migration failure
            FailureMode(
                code: "F11",
                title: "Database Migration Failure",
                userMessage: "The local SQLite schema migration failed. "
                    + "Restart the application; if the error persists, contact support.",
                recovery: .restart,
                severity: .critical
            ),

            // F12 — MCP server unavailable
            FailureMode(
                code: "F12",
                title: "MCP Server Unavailable",
                userMessage: "The in-process MCP server failed to start. "
                    + "Intelligence features will be degraded until a restart.",
                recovery: .restart,
                severity: .error
            ),
        ]
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })
    }()

    // MARK: Lookup

    /// Returns the ``FailureMode`` registered under `code`, or `nil` if unknown.
    ///
    /// - Parameter code: The stable catalogue code, e.g. ``"F05"``.
    public static func entry(for code: String) -> FailureMode? {
        catalogue[code]
    }

    /// All registered entries, sorted by code for stable iteration.
    public static var all: [FailureMode] {
        catalogue.values.sorted { $0.code < $1.code }
    }
}
