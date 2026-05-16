// Domain/MutationCommand.swift — resource_browser bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/resource_browser/schemas/mutation_command.cue
// ADR ref: ADR-0012 (mutating operations policy)

import Foundation

// MARK: - FieldManager

/// The fixed server-side apply field manager identifier.
///
/// Sent in every SSA PATCH request so that field ownership conflicts are
/// traceable to this application. Per ADR-0012 and the CUE schema constraint.
public enum FieldManager {
    /// Canonical field manager identifier for K8sManager.
    public static let k8sManager = "com.archanjo.K8sManager"
}

// MARK: - PropagationPolicy

/// Controls how owned objects are garbage collected after deletion.
///
/// Mirrors the `propagationPolicy` field in `#DeleteResource`.
public enum PropagationPolicy: String, Hashable, Sendable, Codable {
    /// Waits for all owned objects to be deleted before the owner is removed.
    case foreground = "Foreground"
    /// Deletes the owner immediately; GC happens asynchronously.
    case background = "Background"
    /// Removes the owner but leaves owned objects in place.
    case orphan = "Orphan"
}

// MARK: - MutationCommand

/// Sum type representing every mutation the resource_browser context may dispatch.
///
/// Commands are constructed in the UI layer (after confirmation), evaluated by
/// the mutation guard policy, and — if approved — handed to the Kubernetes API
/// adapter. Commands are also serialised into `MutationAuditEntry` before the
/// API call is dispatched. Serialisation MUST redact credential material.
///
/// Mirrors `#MutationCommand` from `mutation_command.cue`.
public enum MutationCommand: Hashable, Sendable, Codable {
    /// Server-side apply (SSA) operation with a full proposed manifest.
    case applyYAML(ApplyYAML)
    /// Targeted replica count update via the `/scale` subresource.
    case scaleReplicas(ScaleReplicas)
    /// Rollout restart via `restartedAt` annotation injection.
    case rolloutRestart(RolloutRestart)
    /// Single-resource delete. Requires double-confirm per ADR-0012.
    case deleteResource(DeleteResource)
    /// Strategic merge patch on `metadata.labels`.
    case labelPatch(LabelPatch)
    /// Strategic merge patch on `metadata.annotations`.
    case annotationPatch(AnnotationPatch)

    /// The GVK of the targeted resource, regardless of command variant.
    public var targetGVK: GroupVersionKind {
        switch self {
        case .applyYAML(let c): c.targetGVK
        case .scaleReplicas(let c): c.targetGVK
        case .rolloutRestart(let c): c.targetGVK
        case .deleteResource(let c): c.targetGVK
        case .labelPatch(let c): c.targetGVK
        case .annotationPatch(let c): c.targetGVK
        }
    }

    /// The resource name, regardless of command variant.
    public var name: String {
        switch self {
        case .applyYAML(let c): c.name
        case .scaleReplicas(let c): c.name
        case .rolloutRestart(let c): c.name
        case .deleteResource(let c): c.name
        case .labelPatch(let c): c.name
        case .annotationPatch(let c): c.name
        }
    }
}

// MARK: - ApplyYAML

/// Server-side apply (SSA) operation.
///
/// The adapter encodes the manifest as UTF-8, sets
/// `Content-Type: application/apply-patch+yaml`, and issues a PATCH request
/// to the resource's REST path.
///
/// Mirrors `#ApplyYAML` from `mutation_command.cue`.
public struct ApplyYAML: Hashable, Sendable, Codable {
    /// Identifies the kind being applied. Must be present in the catalogue.
    public let targetGVK: GroupVersionKind

    /// Required for namespaced resources; `nil` for cluster-scoped.
    public let namespace: String?

    /// Resource name declared in the manifest's `metadata`.
    public let name: String

    /// Full proposed manifest as a YAML string.
    public let manifestYAML: String

    /// SHA-256 hex digest of the UTF-8 encoded `manifestYAML`.
    public let manifestDigest: String

    /// SSA field manager identifier. Must equal `FieldManager.k8sManager`.
    public let fieldManager: String

    /// When `true`, forces ownership over conflicting fields (`force=true`).
    /// Must be an explicit operator opt-in; `false` by default.
    public let forceConflicts: Bool

    public init(
        targetGVK: GroupVersionKind,
        namespace: String?,
        name: String,
        manifestYAML: String,
        manifestDigest: String,
        fieldManager: String = FieldManager.k8sManager,
        forceConflicts: Bool = false
    ) {
        self.targetGVK = targetGVK
        self.namespace = namespace
        self.name = name
        self.manifestYAML = manifestYAML
        self.manifestDigest = manifestDigest
        self.fieldManager = fieldManager
        self.forceConflicts = forceConflicts
    }
}

// MARK: - ScaleReplicas

/// Targeted replica count update via the `/scale` subresource.
///
/// Supported for Deployment, StatefulSet, and ReplicaSet.
/// Mirrors `#ScaleReplicas` from `mutation_command.cue`.
public struct ScaleReplicas: Hashable, Sendable, Codable {
    /// Must be one of Deployment, StatefulSet, or ReplicaSet.
    public let targetGVK: GroupVersionKind

    public let namespace: String
    public let name: String

    /// Target replica count. 0 is permitted (scales to zero).
    public let desiredReplicas: Int

    public init(
        targetGVK: GroupVersionKind,
        namespace: String,
        name: String,
        desiredReplicas: Int
    ) {
        self.targetGVK = targetGVK
        self.namespace = namespace
        self.name = name
        self.desiredReplicas = desiredReplicas
    }
}

// MARK: - RolloutRestart

/// Rollout restart via `kubectl.kubernetes.io/restartedAt` annotation injection.
///
/// Supported for Deployment, DaemonSet, and StatefulSet.
/// Mirrors `#RolloutRestart` from `mutation_command.cue`.
public struct RolloutRestart: Hashable, Sendable, Codable {
    /// Must be one of Deployment, DaemonSet, StatefulSet.
    public let targetGVK: GroupVersionKind

    public let namespace: String
    public let name: String

    /// RFC3339 timestamp injected as the `restartedAt` annotation value.
    public let restartedAt: String

    public init(
        targetGVK: GroupVersionKind,
        namespace: String,
        name: String,
        restartedAt: String
    ) {
        self.targetGVK = targetGVK
        self.namespace = namespace
        self.name = name
        self.restartedAt = restartedAt
    }
}

// MARK: - DeleteResource

/// Single-resource delete. Requires double-confirm per ADR-0012.
///
/// Mirrors `#DeleteResource` from `mutation_command.cue`.
public struct DeleteResource: Hashable, Sendable, Codable {
    public let targetGVK: GroupVersionKind

    /// Required for namespaced resources; `nil` for cluster-scoped.
    public let namespace: String?

    public let name: String

    /// Seconds before force-kill. `nil` = API server default; 0 = immediate.
    public let gracePeriodSeconds: Int?

    /// Garbage collection strategy for owned objects.
    public let propagationPolicy: PropagationPolicy

    public init(
        targetGVK: GroupVersionKind,
        namespace: String?,
        name: String,
        gracePeriodSeconds: Int? = nil,
        propagationPolicy: PropagationPolicy = .background
    ) {
        self.targetGVK = targetGVK
        self.namespace = namespace
        self.name = name
        self.gracePeriodSeconds = gracePeriodSeconds
        self.propagationPolicy = propagationPolicy
    }
}

// MARK: - LabelPatch

/// Strategic merge patch on `metadata.labels`.
///
/// Existing labels whose keys are not present in the patch are preserved.
/// Mirrors `#LabelPatch` from `mutation_command.cue`.
public struct LabelPatch: Hashable, Sendable, Codable {
    public let targetGVK: GroupVersionKind

    /// Required for namespaced resources; `nil` for cluster-scoped.
    public let namespace: String?

    public let name: String

    /// Key-value pairs to add or update. At least one entry required.
    public let labelsToSet: [String: String]

    /// Label keys to remove. Keys absent from the resource are silently ignored.
    public let labelsToRemove: [String]

    public init(
        targetGVK: GroupVersionKind,
        namespace: String?,
        name: String,
        labelsToSet: [String: String],
        labelsToRemove: [String] = []
    ) {
        self.targetGVK = targetGVK
        self.namespace = namespace
        self.name = name
        self.labelsToSet = labelsToSet
        self.labelsToRemove = labelsToRemove
    }
}

// MARK: - AnnotationPatch

/// Strategic merge patch on `metadata.annotations`.
///
/// Existing annotations whose keys are not present in the patch are preserved.
/// Mirrors `#AnnotationPatch` from `mutation_command.cue`.
public struct AnnotationPatch: Hashable, Sendable, Codable {
    public let targetGVK: GroupVersionKind

    /// Required for namespaced resources; `nil` for cluster-scoped.
    public let namespace: String?

    public let name: String

    /// Key-value pairs to add or update. At least one entry required.
    public let annotationsToSet: [String: String]

    /// Annotation keys to remove. Keys absent from the resource are silently ignored.
    public let annotationsToRemove: [String]

    public init(
        targetGVK: GroupVersionKind,
        namespace: String?,
        name: String,
        annotationsToSet: [String: String],
        annotationsToRemove: [String] = []
    ) {
        self.targetGVK = targetGVK
        self.namespace = namespace
        self.name = name
        self.annotationsToSet = annotationsToSet
        self.annotationsToRemove = annotationsToRemove
    }
}
