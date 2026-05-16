// Domain/Security.swift — app_shell bounded context
// DDD role: Value objects — security audit domain types
// Design decision: Security Center is implemented as a read-only feature inside
// AppShell (not a separate BC) because all required data sources are existing ports:
// KubernetesResourceListPort, PrometheusQueryPort, and CRDDiscoveryPort. No new
// inter-context dependencies are introduced. Scoring heuristics live in the ViewModel;
// domain types here are pure value objects with no side effects. This is consistent
// with ADR-0021 (AppShell as orchestration shell) extended for Onda 2 security lens.

import Foundation
import SharedKernel

// MARK: - AlertSeverity

/// Severity classification for a security alert or finding.
public enum AlertSeverity: String, Sendable, CaseIterable, Comparable {
    case critical, high, medium, low, info

    /// Numeric weight used for sort ordering (higher = more severe).
    public var sortWeight: Int {
        switch self {
        case .critical: return 4
        case .high:     return 3
        case .medium:   return 2
        case .low:      return 1
        case .info:     return 0
        }
    }

    public static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.sortWeight < rhs.sortWeight
    }
}

// MARK: - SecurityFindings

/// Aggregated count of findings per severity band.
public struct SecurityFindings: Sendable {
    /// Count of critical-severity findings.
    public let critical: Int
    /// Count of high-severity findings.
    public let high: Int
    /// Count of medium-severity findings.
    public let medium: Int
    /// Count of low-severity findings.
    public let low: Int

    public init(critical: Int, high: Int, medium: Int, low: Int) {
        self.critical = critical
        self.high = high
        self.medium = medium
        self.low = low
    }

    /// A zero-findings baseline value.
    public static let empty = SecurityFindings(critical: 0, high: 0, medium: 0, low: 0)

    /// Total count across all severity bands.
    public var total: Int { critical + high + medium + low }
}

// MARK: - SecurityAlert

/// A discrete security event or audit finding surfaced to the operator.
public struct SecurityAlert: Identifiable, Sendable, Hashable {
    /// Stable identifier for this alert instance.
    public let id: String
    /// Severity classification.
    public let severity: AlertSeverity
    /// Short human-readable description of the finding.
    public let title: String
    /// The Kubernetes resource that triggered this alert, if applicable.
    public let resource: ResourceRef?
    /// ISO-8601 timestamp string (or relative label) for display purposes.
    public let timestamp: String

    public init(
        id: String,
        severity: AlertSeverity,
        title: String,
        resource: ResourceRef? = nil,
        timestamp: String
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.resource = resource
        self.timestamp = timestamp
    }
}

// MARK: - PSSLevel

/// Pod Security Standards admission level.
///
/// Maps directly to the three PSS tiers defined in KEP-2579.
public enum PSSLevel: String, Sendable, CaseIterable {
    /// Minimal restrictions; allows known privilege escalation paths.
    case privileged
    /// Prevents well-known privilege escalation paths.
    case baseline
    /// Enforces the strongest security isolation available.
    case restricted
}

// MARK: - PSSCompliance

/// Aggregated Pod Security Standards compliance snapshot.
public struct PSSCompliance: Sendable {
    /// Number of pods at the `restricted` level.
    public let restricted: Int
    /// Number of pods at the `baseline` level.
    public let baseline: Int
    /// Number of pods at the `privileged` level.
    public let privileged: Int

    public init(restricted: Int = 0, baseline: Int = 0, privileged: Int = 0) {
        self.restricted = restricted
        self.baseline = baseline
        self.privileged = privileged
    }

    /// Total pod count across all PSS levels.
    public var total: Int { restricted + baseline + privileged }
}

// MARK: - RBACOverview

/// High-level RBAC risk summary for a cluster.
public struct RBACOverview: Sendable {
    /// Total count of ClusterRoleBindings present.
    public let clusterRoleBindingCount: Int
    /// Count of bindings to `cluster-admin` for non-system subjects (heuristic risk flag).
    public let overPermissionedBindingCount: Int

    public init(clusterRoleBindingCount: Int = 0, overPermissionedBindingCount: Int = 0) {
        self.clusterRoleBindingCount = clusterRoleBindingCount
        self.overPermissionedBindingCount = overPermissionedBindingCount
    }
}

// MARK: - PrivilegedPodRisk

/// Risk descriptor for a pod exhibiting elevated privilege flags.
public struct PrivilegedPodRisk: Identifiable, Sendable, Hashable {
    /// Stable id derived from namespace + pod name.
    public let id: String
    /// Kubernetes namespace of the pod.
    public let namespace: String
    /// Pod name.
    public let podName: String
    /// `true` when `securityContext.privileged` is set.
    public let isPrivileged: Bool
    /// `true` when `hostNetwork: true`.
    public let hasHostNetwork: Bool
    /// `true` when `hostPID: true`.
    public let hasHostPID: Bool
    /// `true` when the pod runs as `runAsUser: 0` or has no `runAsNonRoot` constraint.
    public let runsAsRoot: Bool
}

// MARK: - ExposedService

/// Summary of a service with potentially external exposure.
public struct ExposedService: Identifiable, Sendable, Hashable {
    /// Stable id derived from namespace + service name.
    public let id: String
    /// Kubernetes namespace.
    public let namespace: String
    /// Service name.
    public let serviceName: String
    /// Service type string (`"LoadBalancer"` or `"NodePort"`).
    public let serviceType: String
}

// MARK: - RBACRisk

/// An RBAC binding or role that carries elevated risk.
public struct RBACRisk: Identifiable, Sendable, Hashable {
    /// Stable id.
    public let id: String
    /// Kind of the RBAC object (`"ClusterRoleBinding"`, `"RoleBinding"`, `"ClusterRole"`, `"Role"`).
    public let kind: String
    /// Object name.
    public let name: String
    /// Namespace (nil for cluster-scoped objects).
    public let namespace: String?
    /// Human-readable reason the object was flagged.
    public let reason: String
}

// MARK: - ImageVulnStatus

/// Vulnerability scan status for a container image.
public enum ImageVulnStatus: String, Sendable {
    /// Trivy CRD is present and the scan completed cleanly.
    case clean
    /// Trivy CRD is present; one or more vulnerabilities found.
    case vulnerable
    /// Trivy CRD is not installed; scanning is unavailable.
    case scanNotConfigured
    /// Trivy CRD present but scan has not run for this image yet.
    case pending
}

// MARK: - ImageSummary

/// Deduplicated container image used across the cluster with vuln status.
public struct ImageSummary: Identifiable, Sendable, Hashable {
    /// Stable id derived from the image reference string.
    public let id: String
    /// Full image reference (e.g. `nginx:1.25`).
    public let imageRef: String
    /// Number of pods currently using this image.
    public let podCount: Int
    /// Vulnerability scan status.
    public let vulnStatus: ImageVulnStatus
    /// Total vulnerability count when status is `.vulnerable`.
    public let vulnCount: Int
}
