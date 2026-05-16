// Views/LoadingStates/ShimmerModifier.swift — app_shell bounded context
// DDD role: View modifier
// ADR ref: ADR-0031 §"Shimmer effect"

import SwiftUI

// MARK: - ShimmerModifier

/// Subtle horizontal shimmer overlay used on top of placeholder layouts.
///
/// The modifier does NOT apply `.redacted(reason: .placeholder)` — callers
/// (e.g. `WorkloadListSkeleton`, `SidebarSkeleton`) already render their own
/// rectangular placeholders. Double-redacting on top of those produced a
/// jittery, layered look; this modifier intentionally limits itself to the
/// moving gradient overlay.
///
/// **Accessibility — Reduce Motion.** When `accessibilityReduceMotion` is on
/// (system preference OR app theme knob), the animation is replaced by a
/// static low-opacity tint so the placeholder still communicates "loading"
/// without repeating motion (ADR-0031 §"Accessibility").
public struct ShimmerModifier: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    public init() {}

    public func body(content: Content) -> some View {
        content
            .overlay(overlay)
            .accessibilityLabel("Loading")
            .onAppear { startAnimationIfAllowed() }
    }

    @ViewBuilder
    private var overlay: some View {
        if reduceMotion {
            staticOverlay
        } else {
            animatedOverlay
        }
    }

    private var animatedOverlay: some View {
        GeometryReader { proxy in
            LinearGradient(
                colors: [
                    .clear,
                    Color.primary.opacity(0.08),
                    .clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: proxy.size.width * 0.45)
            .offset(x: phase * (proxy.size.width + proxy.size.width * 0.45)
                       - proxy.size.width * 0.45)
        }
        .allowsHitTesting(false)
        .clipped()
    }

    private var staticOverlay: some View {
        Color.primary.opacity(0.04)
            .allowsHitTesting(false)
    }

    private func startAnimationIfAllowed() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}

// MARK: - View extension

public extension View {
    /// Applies a subtle shimmer overlay to a placeholder layout.
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
