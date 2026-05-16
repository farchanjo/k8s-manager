// ViewModels/ContextNavigationViewModel.swift — app_shell bounded context
// ADR ref: ADR-0034 (state-driven realtime UI), ADR-0031 (per-resource loading states)

import Foundation
import Dependencies
import Logging
import ContextNavigation
import SharedKernel

private let log = Logger(label: "k8smgr.app_shell.context_navigation")

// MARK: - ContextNavigationViewModel

/// View model for the context navigation screen.
///
/// Owned by `ContextNavigationView`. Drives sidebar read model loading and
/// active context resolution. All mutations happen on the `MainActor` so
/// SwiftUI observation coalesces updates without data races.
@Observable
@MainActor
public final class ContextNavigationViewModel {

    // MARK: State

    /// Lifecycle state of the sidebar read model load operation.
    public var sidebar: AsyncResource<SidebarReadModel> = .idle

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.sidebarReadModel) private var sidebarReadModelPort

    @ObservationIgnored
    @Dependency(\.contextRepository) private var contextRepository

    // MARK: Init

    public init() {}

    // MARK: Intents

    /// Loads the combined sidebar read model (pins + recents) from the port.
    public func loadActiveContext() async {
        sidebar = .loading
        log.info("loadActiveContext start")
        do {
            let model = try await sidebarReadModelPort.currentSidebar()
            log.info("loadActiveContext OK — pinned=\(model.pinned.count) recents=\(model.recents.count)")
            sidebar = .success(model)
        } catch {
            log.error("loadActiveContext FAILED — \(error)")
            sidebar = .failure(error)
        }
    }
}
