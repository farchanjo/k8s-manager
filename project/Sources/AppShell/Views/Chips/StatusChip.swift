// Views/Chips/StatusChip.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0062 (status chips and node conditions)

import SwiftUI

// MARK: - StatusChip

/// Reusable status chip view parameterised by semantic variant, label, and tooltip.
///
/// `StatusChip` is the canonical component for communicating Kubernetes resource
/// health in K8sManager. It satisfies WCAG 1.4.1 by leading every chip with an
/// SF Symbol icon so state is conveyed by both shape and colour.
///
/// Usage:
/// ```swift
/// StatusChip(variant: .success, label: "Ready")
/// StatusChip(variant: .error,   label: "NotReady", tooltip: "kubelet reports node failure")
/// ```
public struct StatusChip: View {

    private let variant: StatusChipVariant
    private let label: String
    private let tooltip: String?

    /// Creates a status chip.
    ///
    /// - Parameters:
    ///   - variant: Semantic severity variant that drives colour and icon selection.
    ///   - label: Short human-readable label displayed inside the chip. Must not be empty.
    ///   - tooltip: Optional hover tooltip populated from the raw Kubernetes condition message.
    public init(variant: StatusChipVariant, label: String, tooltip: String? = nil) {
        self.variant = variant
        self.label = label
        self.tooltip = tooltip
    }

    public var body: some View {
        chipContent
            .accessibilityLabel("\(label) status")
            .accessibilityHint(tooltip ?? "")
            .modifier(TooltipModifier(text: tooltip))
    }

    // MARK: Private subviews

    private var chipContent: some View {
        HStack(spacing: 4) {
            Image(systemName: variant.systemImage)
                .imageScale(.small)
                .symbolRenderingMode(.palette)
                .foregroundStyle(variantColor, Color(.windowBackgroundColor))
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(variantColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(variantColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    /// Design-token colour resolved from the variant.
    ///
    /// Colour names map to the asset catalog entries generated from `design_tokens.cue`.
    private var variantColor: Color {
        switch variant {
        case .success: return Color("statusHealthy")
        case .warning: return Color("statusWarning")
        case .error:   return Color("statusError")
        case .info:    return Color.accentColor
        case .neutral: return Color("statusUnknown")
        }
    }
}

// MARK: - TooltipModifier

/// Applies `.help(_:)` only when tooltip text is non-nil.
private struct TooltipModifier: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("All variants") {
    VStack(alignment: .leading, spacing: 8) {
        StatusChip(variant: .success, label: "Ready",              tooltip: "Node is ready")
        StatusChip(variant: .warning, label: "MemoryPressure",     tooltip: "kubelet has low memory")
        StatusChip(variant: .error,   label: "NotReady",           tooltip: "Node is not ready")
        StatusChip(variant: .info,    label: "Info",               tooltip: nil)
        StatusChip(variant: .neutral, label: "Succeeded",          tooltip: nil)
    }
    .padding()
}
#endif
