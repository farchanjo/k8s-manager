// ViewModels/LLMProviderViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import Foundation
import Dependencies
import Logging
import LLMProvider
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.llm_provider")

// MARK: - LLMProviderViewModel

/// View model for the LLM provider settings screen.
///
/// Owned by `LLMProviderView`. Drives the flat list of configured provider
/// profiles read via `LLMProviderRegistryPort`. All mutations run on the
/// `MainActor` so SwiftUI observation coalesces updates without data races.
@Observable
@MainActor
public final class LLMProviderViewModel {

    // MARK: State

    /// Lifecycle state of the provider list load operation.
    public var providers: AsyncResource<ProviderListReadModel> = .idle

    /// The currently selected provider row, or `nil` when none is selected.
    public var selectedProviderId: UUID?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.llmProviderRegistry) private var registry

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Fetches all configured provider profiles from the registry.
    public func loadProviders() async {
        providers = .loading
        log.info("loadProviders start")
        do {
            let model = try await registry.listReadModel()
            log.info("loadProviders OK — count=\(model.rows.count)")
            providers = .success(model)
        } catch {
            log.error("loadProviders FAILED — \(error)")
            providers = .failure(error)
        }
    }

    /// Marks `row` as the active selection.
    ///
    /// - Parameter row: The provider list row the user tapped.
    public func selectProvider(_ row: ProviderListReadModel.Row) {
        selectedProviderId = row.id
        log.info("selectProvider id=\(row.id) name=\(row.displayName)")
    }

    // MARK: Deferred intents

    /// Deferred — will open the Add Provider sheet once the form is designed.
    ///
    /// - Parameter profile: The new profile to register.
    public func addProvider(_ profile: ProviderProfile) async {
        // TODO(app-shell/llm_provider): implement add-provider flow
        log.info("addProvider deferred id=\(profile.id) kind=\(profile.kind)")
    }
}
