// Actors/LLMProviderRouter.swift — llm_provider bounded context
// DDD role: Application Service / Router Actor
// ADR refs: ADR-0005 (bounded context isolation), ADR-0020 (composition root wiring)
//
// Selects the concrete `LLMStreamingPort` adapter at call time by looking up
// the active `ProviderProfile` from the registry and dispatching into the
// matching factory.

import Foundation
import Logging

// MARK: - RouterError

/// Errors raised by `LLMProviderRouter` before a stream opens.
public enum RouterError: Error, Sendable {
    /// The registry returned no profile for the given identifier.
    case profileNotFound(UUID)

    /// No factory is registered for the profile's `ProviderKind`.
    case unsupportedKind(ProviderKind)

    /// A factory threw while constructing the adapter.
    case factoryFailed(ProviderKind, underlyingError: Error)
}

// MARK: - LLMProviderRouter

/// Routes a streaming request to the correct adapter based on the active
/// `ProviderProfile` resolved from the registry.
///
/// The router is the single composition-root entity that couples `ProviderKind`
/// to concrete adapter implementations. Domain code never imports adapter modules;
/// the composition root injects factories at startup.
///
/// Thread safety: actor isolation ensures the `factories` dictionary and registry
/// reference are accessed without data races.
public actor LLMProviderRouter: LLMStreamingPort {

    // MARK: - State

    private let registry: any LLMProviderRegistryPort
    private let factories: [ProviderKind: @Sendable (ProviderProfile) async throws -> any LLMStreamingPort]
    private let logger: Logger

    // MARK: - Init

    /// Creates a router backed by the given registry and per-kind factories.
    ///
    /// - Parameters:
    ///   - registry: Port that resolves `ProviderProfile` aggregates by `profileId`.
    ///   - factories: Map from `ProviderKind` to a `@Sendable` async throwing closure
    ///     that constructs the matching `LLMStreamingPort` adapter. The factory
    ///     receives the full profile so it can read `modelId`, `baseURL`, etc.
    ///   - logger: Optional structured logger; defaults to `"LLMProviderRouter"`.
    public init(
        registry: any LLMProviderRegistryPort,
        factories: [ProviderKind: @Sendable (ProviderProfile) async throws -> any LLMStreamingPort],
        logger: Logger = Logger(label: "LLMProviderRouter")
    ) {
        self.registry = registry
        self.factories = factories
        self.logger = logger
    }

    // MARK: - LLMStreamingPort

    /// Resolves the profile for `request.profileId`, selects the matching
    /// adapter via `factories`, and delegates the stream to that adapter.
    ///
    /// `nonisolated` satisfies the protocol requirement; actor state is accessed
    /// after an explicit hop inside the spawned `Task`.
    public nonisolated func reply(
        to request: AssistantRequest
    ) -> AsyncThrowingStream<AssistantStreamEvent, Error> {
        let router = self
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let adapter = try await router.resolveAdapter(for: request.profileId)
                    for try await event in adapter.reply(to: request) {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    /// Looks up the profile and constructs the adapter within actor isolation.
    private func resolveAdapter(for profileId: UUID) async throws -> any LLMStreamingPort {
        let profile: ProviderProfile
        do {
            profile = try await registry.profile(id: profileId)
        } catch {
            logger.warning("profile not found", metadata: ["profileId": "\(profileId)"])
            throw RouterError.profileNotFound(profileId)
        }

        guard let factory = factories[profile.kind] else {
            logger.error("no factory for kind", metadata: ["kind": "\(profile.kind.rawValue)"])
            throw RouterError.unsupportedKind(profile.kind)
        }

        do {
            return try await factory(profile)
        } catch {
            logger.error("factory failed", metadata: ["kind": "\(profile.kind.rawValue)"])
            throw RouterError.factoryFailed(profile.kind, underlyingError: error)
        }
    }
}
