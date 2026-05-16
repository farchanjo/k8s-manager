// Views/Welcome/WelcomeTabView.swift — app_shell bounded context
// DDD role: View — Welcome tab content area
// ADR ref: ADR-0054 (Welcome tab and cluster-acquisition entry surface)

import SwiftUI

// MARK: - WelcomeTabView

/// Top-level content view rendered when the workspace `.welcome` tab is active.
///
/// Composes a two-column grid of action tiles (the five cluster-acquisition
/// entry points) with a "Useful Guides" links section beneath. The view is
/// rendered by `ActiveTabContentView` whenever the active tab is `.welcome`.
public struct WelcomeTabView: View {

    @State private var viewModel: WelcomeTabViewModel

    /// Designated initialiser.
    ///
    /// - Parameter viewModel: View model that holds the action catalogue and
    ///   dispatches invocations. Defaults to a fresh instance with the main
    ///   bundle and no handler — composition root callers should inject a
    ///   wired view model with the appropriate flow router.
    public init(viewModel: WelcomeTabViewModel? = nil) {
        if let viewModel {
            _viewModel = State(wrappedValue: viewModel)
        } else {
            _viewModel = State(wrappedValue: WelcomeTabViewModel())
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                actionGrid
                Divider().padding(.vertical, 4)
                UsefulGuidesSection(links: viewModel.guideLinks)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("WelcomeTabView")
    }

    // MARK: Sub-views

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome to K8sManager")
                .font(.system(size: 22, weight: .semibold))
            Text("Connect a cluster to get started, or restart the onboarding tour.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }

    private var actionGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 240), spacing: 14),
                GridItem(.flexible(minimum: 240), spacing: 14),
            ],
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(viewModel.actions, id: \.self) { action in
                WelcomeActionTile(action: action) {
                    viewModel.invoke(action)
                }
            }
        }
    }
}
