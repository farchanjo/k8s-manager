// Domain/LoadingState.swift — app_shell bounded context
// DDD role: ValueObject
// CUE source: docs/arch/contexts/app_shell/schemas/loading_state.cue
// ADR ref: ADR-0031

import Foundation

// MARK: - LoadingPresentation

/// Selects the visual mode for a loading state.
///
/// Resolved by the view from the expected duration of the underlying operation —
/// NOT by the domain layer.
public enum LoadingPresentation: String, Sendable, Codable {
    /// `.redacted(reason: .placeholder)` with fixed template layout.
    /// Use when layout is known and estimated duration > 100 ms.
    case skeleton
    /// Skeleton + diagonal gradient animation. Use for content-heavy or layout-unknown surfaces.
    case shimmer
    /// Indeterminate `ProgressView` (centered). Use for quick ops < 500 ms.
    case spinner
    /// Determinate `ProgressView`. Use when total unit count is known.
    case progressBar
}

// MARK: - LoadingConfig

/// Presentation configuration including the 200 ms throttle threshold.
public struct LoadingConfig: Sendable, Codable {
    /// Visual mode for the loading state.
    public let presentation: LoadingPresentation
    /// Milliseconds before the loading UI is shown (suppresses flash for fast ops).
    public let showAfterMillis: Int

    public static let `default` = LoadingConfig(presentation: .skeleton, showAfterMillis: 200)

    public init(presentation: LoadingPresentation = .skeleton, showAfterMillis: Int = 200) {
        self.presentation = presentation
        self.showAfterMillis = showAfterMillis
    }
}

// MARK: - EmptyStateActionType

/// The kind of action triggered by the empty-state call-to-action button.
public enum EmptyStateActionType: String, Sendable, Codable {
    case configure, retry, reload
}

// MARK: - EmptyState

/// Visual and interactive content shown when an `AsyncResource` succeeds with an empty collection.
///
/// Authored statically per resource kind — never generated dynamically.
public struct EmptyState: Sendable, Codable {
    /// Concise statement of absence (3–80 chars).
    public let title: String
    /// Contextual explanation and guidance (10–300 chars).
    public let message: String
    /// Optional CTA button label (2–40 chars).
    public let actionLabel: String?
    /// Required when `actionLabel` is present.
    public let actionType: EmptyStateActionType?

    public init(
        title: String,
        message: String,
        actionLabel: String? = nil,
        actionType: EmptyStateActionType? = nil
    ) {
        self.title = title
        self.message = message
        self.actionLabel = actionLabel
        self.actionType = actionType
    }
}

// MARK: - Canonical empty states

extension EmptyState {
    /// Shown when `watchPods` returns an empty list.
    public static let podsInNamespace = EmptyState(
        title: "No pods in this namespace",
        message: "Deployments may not have scheduled pods here yet, or all pods have been removed.",
        actionLabel: "Switch namespace",
        actionType: .reload
    )

    /// Shown when no cluster contexts are configured.
    public static let clusters = EmptyState(
        title: "No clusters configured",
        message: "Import a kubeconfig file to connect to a Kubernetes cluster.",
        actionLabel: "Add cluster",
        actionType: .configure
    )

    /// Shown when the deployment list is empty.
    public static let deployments = EmptyState(
        title: "No deployments in this namespace",
        message: "No Deployment resources exist in the selected namespace."
    )

    /// Shown when command palette search returns zero results.
    public static let searchResults = EmptyState(
        title: "No results",
        message: "Try a different search term or check spelling."
    )

    /// Shown in Settings → Activity Log when no toasts have been emitted.
    public static let toastHistory = EmptyState(
        title: "No activity yet",
        message: "Notification history will appear here after your first operation."
    )
}
