// Views/LoadingStates/ErrorStateView.swift — app_shell bounded context
// DDD role: View — uniform error state across async surfaces
// ADR ref: ADR-0031 §"Error states"

import SwiftUI

// MARK: - ErrorStateView

/// Uniform error-state component for any `AsyncResource` that reaches
/// `.failure`. Title summarises the failure surface; `error` carries the
/// underlying cause shown behind a "Show details" disclosure to avoid
/// alarming casual operators (ADR-0031 §"Error states").
///
/// Retry vs Dismiss is driven by `retryable`. The view never silently
/// hides errors — non-retryable failures still display a Dismiss button so
/// the operator acknowledges them explicitly.
public struct ErrorStateView: View {

    public let title: String
    public let error: Error
    public let retryable: Bool
    public let onRetry: (() -> Void)?
    public let onDismiss: (() -> Void)?

    @State private var showDetails: Bool = false

    public init(
        title: String,
        error: Error,
        retryable: Bool = true,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.error = error
        self.retryable = retryable
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.orange)
            Text(title)
                .font(.headline)
            DisclosureGroup("Show details", isExpanded: $showDetails) {
                Text(error.localizedDescription)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
                    .frame(maxWidth: 480)
            }
            .frame(maxWidth: 360)
            actionButtons
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(title)")
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if retryable, let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
            if let onDismiss {
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
            }
        }
        .padding(.top, 4)
    }
}
