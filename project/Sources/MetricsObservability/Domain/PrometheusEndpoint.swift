// Domain/PrometheusEndpoint.swift — metrics_observability bounded context
// DDD role: AggregateRoot
// CUE source: docs/arch/contexts/metrics_observability/schemas/prometheus_endpoint.cue

import Foundation

// MARK: - DiscoverySource

/// How a `PrometheusEndpoint` was found or configured.
///
/// Mirrors the `discovery_source` field from `prometheus_endpoint.cue`.
/// Cases are ordered by precedence (highest first).
public enum DiscoverySource: String, Hashable, Sendable, Codable, CaseIterable {
    /// Operator-supplied URL in per-cluster settings. Highest precedence.
    case manualOverride = "manual_override"

    /// Fixed kube-prometheus-stack in-cluster address via API-server proxy.
    case wellKnown = "well_known"

    /// Service carrying label `app.kubernetes.io/name=prometheus`.
    case autoLabel = "auto_label"

    /// Service carrying annotation `prometheus.io/scrape=true`.
    case autoAnnotation = "auto_annotation"
}

// MARK: - AuthStrategy

/// Authentication strategy for requests to a `PrometheusEndpoint`.
///
/// Mirrors the `auth_strategy` field from `prometheus_endpoint.cue`.
public enum AuthStrategy: String, Hashable, Sendable, Codable, CaseIterable {
    /// No `Authorization` header is added.
    case none

    /// Forwards the bearer token from the current `KubernetesSession`.
    case bearerInherit = "bearer_inherit"

    /// Uses a separate operator-supplied bearer token.
    case bearerExplicit = "bearer_explicit"
}

// MARK: - EndpointStatus

/// Connectivity and authentication state as determined by the last health probe.
///
/// Mirrors the `status` field from `prometheus_endpoint.cue`.
public enum EndpointStatus: String, Hashable, Sendable, Codable, CaseIterable {
    /// No probe has been attempted yet.
    case unknown

    /// Last probe returned HTTP 200.
    case healthy

    /// Connection refused, timeout, or DNS failure.
    case unreachable

    /// HTTP 401 or 403 received.
    case unauthorized
}

// MARK: - PrometheusEndpoint

/// Aggregate root representing a discovered or manually configured
/// Prometheus instance scoped to one Kubernetes context.
///
/// Mirrors `#PrometheusEndpoint` from `prometheus_endpoint.cue`.
/// Identified by a UUIDv7. Mutable only through domain operations
/// (health probe updates, operator override) — never from UI code.
public struct PrometheusEndpoint: Hashable, Sendable, Codable {
    /// Stable UUIDv7 identifier for this endpoint record.
    public let id: UUID

    /// Reference to the `KubernetesContext` this endpoint belongs to.
    public let kubernetesContextId: UUID

    /// Base URL of the Prometheus HTTP API. Must use `http` or `https` scheme.
    public let url: String

    /// How this endpoint was discovered or configured.
    public let discoverySource: DiscoverySource

    /// Authentication strategy for requests to this endpoint.
    public let authStrategy: AuthStrategy

    /// When `true`, TLS certificate verification is skipped.
    /// Must not be set automatically — operator opt-in only.
    public let insecureSkipTLSVerify: Bool

    /// Connectivity and authentication status from the last health probe.
    public let status: EndpointStatus

    /// RFC 3339 timestamp of the last health probe attempt.
    /// `nil` when no probe has been attempted.
    public let lastProbedAt: String?

    /// Prometheus server version string (e.g., `"3.7.1"`).
    /// `nil` until a successful probe completes.
    public let version: String?

    public init(
        id: UUID,
        kubernetesContextId: UUID,
        url: String,
        discoverySource: DiscoverySource,
        authStrategy: AuthStrategy,
        insecureSkipTLSVerify: Bool = false,
        status: EndpointStatus = .unknown,
        lastProbedAt: String? = nil,
        version: String? = nil
    ) {
        self.id = id
        self.kubernetesContextId = kubernetesContextId
        self.url = url
        self.discoverySource = discoverySource
        self.authStrategy = authStrategy
        self.insecureSkipTLSVerify = insecureSkipTLSVerify
        self.status = status
        self.lastProbedAt = lastProbedAt
        self.version = version
    }

    /// Returns a copy of the endpoint with updated health probe results.
    ///
    /// - Parameters:
    ///   - status: New connectivity/auth status.
    ///   - probedAt: RFC 3339 timestamp of the probe.
    ///   - version: Server version string returned by the probe, if any.
    public func probedWith(
        status: EndpointStatus,
        probedAt: String,
        version: String? = nil
    ) -> PrometheusEndpoint {
        PrometheusEndpoint(
            id: id,
            kubernetesContextId: kubernetesContextId,
            url: url,
            discoverySource: discoverySource,
            authStrategy: authStrategy,
            insecureSkipTLSVerify: insecureSkipTLSVerify,
            status: status,
            lastProbedAt: probedAt,
            version: version ?? self.version
        )
    }
}
