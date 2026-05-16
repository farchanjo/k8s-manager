// Domain/ResourceBrowserService.swift — resource_browser bounded context
// DDD role: DomainService
// CUE source: docs/arch/contexts/resource_browser/schemas/resource_browser_service.cue
// ADR refs: ADR-0012 (mutation policy), ADR-0013 (kind catalogue)

import Foundation

// MARK: - MutationOutcomeStatus

/// Status returned by domain services after a mutation is processed.
///
/// Mirrors `#MutationOutcome.status` from `resource_browser_service.cue`.
public enum MutationOutcomeStatus: String, Hashable, Sendable, Codable {
    /// Kubernetes API returned 2xx; mutation was applied.
    case succeeded
    /// Mutation guard policy denied the command.
    case deniedByPolicy = "denied_by_policy"
    /// API returned an error or a network error occurred.
    case failed
    /// Operator dismissed the confirmation modal.
    case cancelled
}

// MARK: - MutationResult

/// Transient return value from `MutationDispatchService`.
///
/// Links back to the persisted audit row via `auditEntryId`. Not stored in the
/// database directly; the persisted form lives in `MutationAuditEntry`.
/// Mirrors `#MutationOutcome` from `resource_browser_service.cue`.
public struct MutationResult: Sendable {
    /// Links this outcome back to the persisted audit row.
    public let auditEntryId: UUID

    /// Final status of the mutation attempt.
    public let status: MutationOutcomeStatus

    /// HTTP status code returned by the Kubernetes API server.
    /// `nil` for denied-by-policy or cancelled outcomes.
    public let kubernetesStatusCode: Int?

    /// Operator-visible reason string. MUST NOT contain credential material.
    public let detail: String?

    public init(
        auditEntryId: UUID,
        status: MutationOutcomeStatus,
        kubernetesStatusCode: Int? = nil,
        detail: String? = nil
    ) {
        self.auditEntryId = auditEntryId
        self.status = status
        self.kubernetesStatusCode = kubernetesStatusCode
        self.detail = detail
    }
}

// MARK: - ResourceBrowserServiceConfig

/// Configuration value object for the `ResourceBrowserService` domain service.
///
/// Carries the identity of the service instance and the cluster context it is
/// scoped to. Mirrors `#ResourceBrowserService` from `resource_browser_service.cue`.
public struct ResourceBrowserServiceConfig: Sendable {
    /// Unique identifier for this service instance. UUIDv7.
    public let id: UUID

    /// Cluster context this service instance is scoped to.
    public let kubernetesContextId: UUID

    /// SSA field manager string sent in every PATCH/apply request.
    public let activeFieldManager: String

    public init(
        id: UUID = UUID(),
        kubernetesContextId: UUID,
        activeFieldManager: String = FieldManager.k8sManager
    ) {
        self.id = id
        self.kubernetesContextId = kubernetesContextId
        self.activeFieldManager = activeFieldManager
    }
}

// MARK: - SensitiveAnnotationKeys

/// Default deny-list of annotation key suffixes whose values are redacted.
///
/// Mirrors `#MutationCommandFactory.sensitiveAnnotationKeys` from
/// `resource_browser_service.cue`. Callers may extend at construction time.
public enum SensitiveAnnotationKeys {
    public static let defaults: [String] = [
        "kubectl.kubernetes.io/last-applied-configuration",
        "token",
        "password",
        "secret",
    ]
}

// MARK: - MutationCommandFactoryConfig

/// Configuration value object for the `MutationCommandFactory` domain service.
///
/// Mirrors `#MutationCommandFactory` from `resource_browser_service.cue`.
public struct MutationCommandFactoryConfig: Sendable {
    /// Unique identifier for this factory instance (for tracing).
    public let id: UUID

    /// Propagated into every command produced by this factory.
    public let kubernetesContextId: UUID

    /// Annotation key suffixes whose values are redacted to `"<redacted>"`.
    public let sensitiveAnnotationKeys: [String]

    public init(
        id: UUID = UUID(),
        kubernetesContextId: UUID,
        sensitiveAnnotationKeys: [String] = SensitiveAnnotationKeys.defaults
    ) {
        self.id = id
        self.kubernetesContextId = kubernetesContextId
        self.sensitiveAnnotationKeys = sensitiveAnnotationKeys
    }
}

// MARK: - MutationDispatchServiceConfig

/// Configuration value object for the `MutationDispatchService` domain service.
///
/// Mirrors `#MutationDispatchService` from `resource_browser_service.cue`.
public struct MutationDispatchServiceConfig: Sendable {
    /// Unique identifier for this dispatcher instance (for tracing).
    public let id: UUID

    /// Scopes all dispatch operations to one cluster.
    public let kubernetesContextId: UUID

    /// Field manager string passed in SSA PATCH requests.
    public let fieldManagerId: String

    /// Maximum age of a confirmation token in seconds. Default 300 (5 minutes).
    public let maxConfirmationTokenAgeSeconds: Int

    public init(
        id: UUID = UUID(),
        kubernetesContextId: UUID,
        fieldManagerId: String = FieldManager.k8sManager,
        maxConfirmationTokenAgeSeconds: Int = 300
    ) {
        self.id = id
        self.kubernetesContextId = kubernetesContextId
        self.fieldManagerId = fieldManagerId
        self.maxConfirmationTokenAgeSeconds = maxConfirmationTokenAgeSeconds
    }
}
