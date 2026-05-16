// Views/LoadingStates/EmptyStateView.swift — app_shell bounded context
// DDD role: View — uniform empty state across resource lists
// ADR ref: ADR-0031 §"Empty states"

import SwiftUI

// MARK: - EmptyStateView

/// Uniform empty-state component used whenever an `AsyncResource` resolves
/// to `.success` with an empty collection.
///
/// The component is intentionally thin — callers compose the right copy
/// (`"No pods in this namespace"`, `"This cluster has no deployments"`) and
/// the right action label (`"Switch namespace"`, `"Reload"`). The icon
/// defaults to `tray` but should be overridden per kind for context.
public struct EmptyStateView: View {

    public let title: String
    public let message: String?
    public let systemImage: String
    public let actionLabel: String?
    public let onAction: (() -> Void)?

    public init(
        title: String,
        message: String? = nil,
        systemImage: String = "tray",
        actionLabel: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionLabel = actionLabel
        self.onAction = onAction
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            if let actionLabel, let onAction {
                Button(actionLabel, action: onAction)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message ?? "")")
    }
}
