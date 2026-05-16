// Actors/MutationDispatchService.swift — resource_browser bounded context
// DDD role: DomainService (actor)
// ADR refs: ADR-0012 (mutation policy, confirmation-token gate, audit trail)

import Dependencies
import Foundation
import Logging
import SharedKernel

// MARK: - MutationDispatchError

/// Errors that may prevent a command from being dispatched.
public enum MutationDispatchError: Error, Sendable {
    /// The confirmation token is absent or has expired (ADR-0012 §5 min gate).
    case staleConfirmationToken(age: TimeInterval)
    /// The audit port refused to record the entry (duplicate requestId).
    case duplicateRequestId(UUID)
    /// The Kubernetes API returned an error after dispatch.
    case apiError(MutationError)
    /// The audit entry could not be persisted; command aborted for safety.
    case auditFailure(AuditError)
}

// MARK: - MutationDispatchService

/// Receives an approved `MutationCommand` and orchestrates its execution.
///
/// Flow:
/// 1. Validate the confirmation-token age against `config.maxConfirmationTokenAgeSeconds`.
/// 2. Persist a `MutationAuditEntry` with `outcome = .cancelled` (pre-dispatch sentinel).
/// 3. Invoke `kubernetesResourceMutation` to issue the API call.
/// 4. Update the audit entry with the final outcome.
///
/// All steps run inside the actor to serialise access to the audit chain state.
public actor MutationDispatchService {

    // MARK: - Dependencies

    @Dependency(\.kubernetesResourceMutation) private var mutationPort
    @Dependency(\.mutationAudit) private var auditPort

    // MARK: - State

    /// Configuration for this dispatcher instance.
    public let config: MutationDispatchServiceConfig

    private let logger: Logger

    // MARK: - Initialiser

    /// Creates the dispatcher scoped to one cluster context.
    public init(
        config: MutationDispatchServiceConfig,
        logger: Logger = Logger(label: "resource_browser.mutation_dispatch")
    ) {
        self.config = config
        self.logger = logger
    }

    // MARK: - Public API

    /// Dispatches an approved `MutationCommand` to the Kubernetes API.
    ///
    /// The `confirmationToken` must have been generated within the window
    /// defined by `config.maxConfirmationTokenAgeSeconds` (default 300 s).
    ///
    /// - Parameters:
    ///   - command: The fully constructed, approved mutation command.
    ///   - confirmationToken: UUIDv7 generated when the confirmation modal was shown.
    ///   - tokenIssuedAt: The instant the confirmation modal appeared.
    ///   - previousEntryDigest: SHA-256 of the preceding audit row for chain integrity.
    /// - Returns: A `MutationResult` linking back to the persisted audit entry.
    /// - Throws: `MutationDispatchError` if the token is stale, the audit write fails,
    ///           or the Kubernetes API returns an error.
    public func dispatch(
        _ command: MutationCommand,
        confirmationToken: UUID,
        tokenIssuedAt: Date,
        previousEntryDigest: String
    ) async throws -> MutationResult {
        let age = Date().timeIntervalSince(tokenIssuedAt)
        guard age <= Double(config.maxConfirmationTokenAgeSeconds) else {
            throw MutationDispatchError.staleConfirmationToken(age: age)
        }

        let entryId = UUIDv7.generate(now: Date())
        let requestedAt = ISO8601DateFormatter().string(from: Date())

        let auditEntry = MutationAuditEntry(
            id: entryId,
            requestedAt: requestedAt,
            kubernetesContextId: config.kubernetesContextId,
            command: command,
            outcome: .cancelled,
            confirmationToken: confirmationToken,
            previousEntryDigest: previousEntryDigest
        )

        do {
            try await auditPort.record(auditEntry)
        } catch let auditErr as AuditError {
            if case .duplicateEntry(let id) = auditErr {
                throw MutationDispatchError.duplicateRequestId(id)
            }
            throw MutationDispatchError.auditFailure(auditErr)
        }

        let statusCode: Int
        do {
            statusCode = try await issueAPICall(command: command)
        } catch let mutErr as MutationError {
            let completedAt = ISO8601DateFormatter().string(from: Date())
            try? await auditPort.complete(
                id: entryId,
                outcome: .failed,
                completedAt: completedAt,
                kubernetesStatusCode: nil
            )
            logger.warning("Mutation API call failed: \(mutErr)")
            throw MutationDispatchError.apiError(mutErr)
        }

        let completedAt = ISO8601DateFormatter().string(from: Date())
        try? await auditPort.complete(
            id: entryId,
            outcome: .succeeded,
            completedAt: completedAt,
            kubernetesStatusCode: statusCode
        )

        logger.info("Mutation succeeded: gvk=\(command.targetGVK.kind) name=\(command.name) status=\(statusCode)")
        return MutationResult(
            auditEntryId: entryId,
            status: .succeeded,
            kubernetesStatusCode: statusCode
        )
    }

    // MARK: - Private

    /// Routes the command to the appropriate port method.
    private func issueAPICall(command: MutationCommand) async throws -> Int {
        switch command {
        case .applyYAML(let c):
            return try await mutationPort.applyYAML(command: c, contextId: config.kubernetesContextId)
        case .scaleReplicas(let c):
            return try await mutationPort.scaleReplicas(command: c, contextId: config.kubernetesContextId)
        case .rolloutRestart(let c):
            return try await mutationPort.rolloutRestart(command: c, contextId: config.kubernetesContextId)
        case .deleteResource(let c):
            return try await mutationPort.deleteResource(command: c, contextId: config.kubernetesContextId)
        case .labelPatch(let c):
            return try await mutationPort.labelPatch(command: c, contextId: config.kubernetesContextId)
        case .annotationPatch(let c):
            return try await mutationPort.annotationPatch(command: c, contextId: config.kubernetesContextId)
        }
    }
}

