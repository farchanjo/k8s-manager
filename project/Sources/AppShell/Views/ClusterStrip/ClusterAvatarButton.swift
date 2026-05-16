// Views/ClusterStrip/ClusterAvatarButton.swift — app_shell bounded context
// ADR ref: ADR-0051 (cluster strip avatar chip spec)

import SwiftUI
import SharedKernel

// MARK: - ClusterAvatarButton

/// 40×40 rounded-square avatar chip for a single pinned cluster.
///
/// Renders:
/// - Background fill from `pin.colorHex`.
/// - Initials text: white, bold, centered.
/// - 2 pt `accentColor` stroke border when `isActive`.
/// - Subtle drop shadow.
/// - Scale animation on hover (macOS `.onHover`).
/// - Green/red health dot in the bottom-right corner.
///
/// Health dot color is derived from a simple `isHealthy` flag injected by the
/// parent so the button stays testable without a live Kubernetes dependency.
public struct ClusterAvatarButton: View {

    // MARK: Input

    let pin: ClusterStripPin
    let isActive: Bool
    var isHealthy: Bool? = nil  // nil → unknown (grey dot)

    // MARK: Private state

    @State private var isHovered = false

    // MARK: Body

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarBody
            healthDot
        }
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { isHovered = $0 }
        .help(pin.displayName)
    }

    // MARK: Sub-views

    private var avatarBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: pin.colorHex) ?? .accentColor)
            Text(pin.initials)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 40, height: 40)
        .overlay(activeBorder)
        .shadow(color: .black.opacity(0.18), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private var activeBorder: some View {
        if isActive {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor, lineWidth: 2)
        }
    }

    private var healthDot: some View {
        Circle()
            .fill(healthDotColor)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
            .offset(x: 2, y: 2)
    }

    private var healthDotColor: Color {
        switch isHealthy {
        case true: return .green
        case false: return .red
        case nil: return .gray
        }
    }
}

// MARK: - Color(hex:)

private extension Color {
    /// Creates a `Color` from a CSS hex string (`"#RRGGBB"` or `"RRGGBB"`).
    init?(hex: String) {
        let stripped = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard stripped.count == 6, let value = UInt64(stripped, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xff) / 255
        let g = Double((value >> 8) & 0xff) / 255
        let b = Double(value & 0xff) / 255
        self.init(red: r, green: g, blue: b)
    }
}
