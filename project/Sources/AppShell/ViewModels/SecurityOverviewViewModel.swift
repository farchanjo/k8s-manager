// ViewModels/SecurityOverviewViewModel.swift — app_shell bounded context
// DDD role: ViewModel — security score + findings aggregator
// ADR ref: ADR-0021 (AppShell orchestration shell extended for Onda 2 security lens)

import Foundation
import Logging
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.security_overview")

// MARK: - SecurityOverviewViewModel

/// View model for the Security Center overview dashboard.
///
/// Computes a heuristic 0-100 security score by querying existing ports:
/// pod list, service list, RBAC bindings, and roles. All mutations are
/// `@MainActor`-isolated; no data races across actor boundaries.
///
/// Scoring deductions (capped at 0):
/// - `-10` per privileged pod.
/// - `-5` per pod running as root without `runAsNonRoot`.
/// - `-15` per cluster-admin binding for a non-system subject.
/// - `-3` per Role/ClusterRole with wildcard verbs.
/// - `-8` per LoadBalancer service in a namespace with no NetworkPolicy.
@Observable
@MainActor
public final class SecurityOverviewViewModel {

    // MARK: - Observed state

    /// Current heuristic security score (0–100). Starts at 100 (no data yet).
    public var score: Int = 100
    /// Aggregated finding counts per severity band.
    public var findings: SecurityFindings = .empty
    /// Most-recent security alerts, capped at 10, sorted by severity descending.
    public var topAlerts: [SecurityAlert] = []
    /// Pod Security Standards compliance snapshot.
    public var podSecurityCompliance: PSSCompliance = .init()
    /// High-level RBAC summary.
    public var rbacOverview: RBACOverview = .init()
    /// Load-lifecycle state.
    public var loadState: AsyncResource<Void> = .idle

    // MARK: - Ports (injected via dependency key; stubs in tests)

    @ObservationIgnored
    var listPort: any KubernetesSecurityListPort = UnimplementedSecurityListPort()

    // MARK: - Init

    public init() {}

    // MARK: - Public intents

    /// Starts a full security audit for the given cluster.
    ///
    /// - Parameter clusterId: The cluster to audit.
    public func start(clusterId: ClusterId) async {
        log.info("security audit start clusterId=\(clusterId.rawValue)")
        loadState = .loading
        do {
            let snapshot = try await listPort.fetchSecuritySnapshot(clusterId: clusterId)
            apply(snapshot: snapshot)
            loadState = .success(())
            log.info("security audit OK score=\(score)")
        } catch {
            log.error("security audit FAILED — \(error)")
            loadState = .failure(error)
        }
    }

    /// Re-runs the audit for the most recently audited cluster.
    public func reload(clusterId: ClusterId) async {
        await start(clusterId: clusterId)
    }

    // MARK: - Private

    private func apply(snapshot: SecuritySnapshot) {
        podSecurityCompliance = snapshot.pssCompliance
        rbacOverview = snapshot.rbacOverview
        topAlerts = Array(snapshot.alerts.prefix(10))
        findings = buildFindings(from: snapshot)
        score = computeScore(snapshot: snapshot)
    }

    private func buildFindings(from snapshot: SecuritySnapshot) -> SecurityFindings {
        let critical = snapshot.alerts.filter { $0.severity == .critical }.count
        let high     = snapshot.alerts.filter { $0.severity == .high }.count
        let medium   = snapshot.alerts.filter { $0.severity == .medium }.count
        let low      = snapshot.alerts.filter { $0.severity == .low }.count
        return SecurityFindings(critical: critical, high: high, medium: medium, low: low)
    }

    /// Computes the 0–100 heuristic score from audit results.
    func computeScore(snapshot: SecuritySnapshot) -> Int {
        var deduction = 0
        deduction += snapshot.privilegedPodCount * 10
        deduction += snapshot.rootPodCount * 5
        deduction += snapshot.clusterAdminBindingCount * 15
        deduction += snapshot.wildcardRoleCount * 3
        deduction += snapshot.exposedLoadBalancerCount * 8
        return max(0, 100 - deduction)
    }
}

// MARK: - SecuritySnapshot

/// Intermediate data transfer object carrying all audit inputs for one cluster.
///
/// Produced by `KubernetesSecurityListPort.fetchSecuritySnapshot`. The ViewModel
/// reads from this struct; the port fills it from the Kubernetes API.
public struct SecuritySnapshot: Sendable {
    /// Alerts derived from Warning events and heuristic flags.
    public let alerts: [SecurityAlert]
    /// PSS compliance counts.
    public let pssCompliance: PSSCompliance
    /// RBAC summary.
    public let rbacOverview: RBACOverview
    /// Number of pods with `privileged: true` (drives score deduction).
    public let privilegedPodCount: Int
    /// Number of pods running as root without `runAsNonRoot` (drives score deduction).
    public let rootPodCount: Int
    /// Number of cluster-admin bindings for non-system subjects (drives score deduction).
    public let clusterAdminBindingCount: Int
    /// Number of roles/cluster-roles containing wildcard verbs (drives score deduction).
    public let wildcardRoleCount: Int
    /// Number of LoadBalancer services in namespaces with no NetworkPolicy (drives score deduction).
    public let exposedLoadBalancerCount: Int

    public init(
        alerts: [SecurityAlert] = [],
        pssCompliance: PSSCompliance = .init(),
        rbacOverview: RBACOverview = .init(),
        privilegedPodCount: Int = 0,
        rootPodCount: Int = 0,
        clusterAdminBindingCount: Int = 0,
        wildcardRoleCount: Int = 0,
        exposedLoadBalancerCount: Int = 0
    ) {
        self.alerts = alerts
        self.pssCompliance = pssCompliance
        self.rbacOverview = rbacOverview
        self.privilegedPodCount = privilegedPodCount
        self.rootPodCount = rootPodCount
        self.clusterAdminBindingCount = clusterAdminBindingCount
        self.wildcardRoleCount = wildcardRoleCount
        self.exposedLoadBalancerCount = exposedLoadBalancerCount
    }
}

// MARK: - KubernetesSecurityListPort

/// Port contract for fetching security-relevant cluster data.
///
/// Production adapters query `pods`, `services`, `clusterrolebindings`, `roles`,
/// and `clusterroles` via `KubernetesResourceListPort`.
public protocol KubernetesSecurityListPort: Sendable {
    /// Fetches a complete security snapshot for the given cluster.
    ///
    /// - Parameter clusterId: Target cluster identifier.
    /// - Returns: A `SecuritySnapshot` filled from the Kubernetes API.
    /// - Throws: Any transport or API error.
    func fetchSecuritySnapshot(clusterId: ClusterId) async throws -> SecuritySnapshot
}

// MARK: - Unimplemented default

private struct UnimplementedSecurityListPort: KubernetesSecurityListPort {
    func fetchSecuritySnapshot(clusterId: ClusterId) async throws -> SecuritySnapshot {
        preconditionFailure("KubernetesSecurityListPort not injected — use SecurityOverviewViewModel(listPort:)")
    }
}
