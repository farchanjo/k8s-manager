// Feature.swift — sidebar navigation enum
// Bounded context: app_shell
import Foundation

/// Identifies each top-level feature panel accessible from the sidebar.
///
/// Conforms to `CaseIterable` so the sidebar can drive its `List` directly
/// from `Feature.allCases` without a separate manifest.
public enum Feature: String, CaseIterable, Identifiable, Hashable, Sendable {
    case clusters
    case contexts
    case resources
    case chat
    case intelligence
    case providers
    case persistence
    case helm
    case metrics
    case portForward
    case terminal

    /// Stable identity used by `NavigationSplitView` selection binding.
    public var id: String { rawValue }

    /// Human-readable label shown in the sidebar row.
    public var title: String {
        switch self {
        case .clusters:    return "Clusters"
        case .contexts:    return "Contexts"
        case .resources:   return "Resources"
        case .chat:        return "Assistant"
        case .intelligence: return "Intelligence"
        case .providers:   return "LLM Providers"
        case .persistence: return "Local Data"
        case .helm:        return "Helm"
        case .metrics:     return "Metrics"
        case .portForward: return "Port Forward"
        case .terminal:    return "Terminal"
        }
    }

    /// SF Symbol name for the sidebar `Label`.
    public var systemImage: String {
        switch self {
        case .clusters:    return "cube.transparent"
        case .contexts:    return "arrow.triangle.branch"
        case .resources:   return "list.bullet.rectangle"
        case .chat:        return "bubble.left.and.bubble.right"
        case .intelligence: return "brain"
        case .providers:   return "key.horizontal"
        case .persistence: return "internaldrive"
        case .helm:        return "shippingbox"
        case .metrics:     return "chart.line.uptrend.xyaxis"
        case .portForward: return "arrow.left.arrow.right.circle"
        case .terminal:    return "terminal"
        }
    }
}
