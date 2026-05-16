// Views/Welcome/UsefulGuidesSection.swift — app_shell bounded context
// DDD role: View — Welcome tab Useful Guides links section
// ADR ref: ADR-0054 (Welcome tab and cluster-acquisition entry surface)

import SwiftUI

// MARK: - UsefulGuidesSection

/// Renders the "Useful Guides" section that appears below the action tiles.
///
/// Each entry is a `Link` control opening the configured URL in the default
/// browser. When a link target is missing (Info.plist key absent at app
/// bundle build time) the entry renders as a disabled label so operators do
/// not see a dead link.
struct UsefulGuidesSection: View {

    let links: [WelcomeGuideLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Useful Guides")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(links) { link in
                    linkRow(link)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Sub-views

    @ViewBuilder
    private func linkRow(_ link: WelcomeGuideLink) -> some View {
        if let url = link.url {
            Link(destination: url) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                    Text(link.title)
                        .font(.system(size: 13))
                }
                .foregroundStyle(.tint)
            }
            .accessibilityLabel(link.title)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                Text(link.title)
                    .font(.system(size: 13))
            }
            .foregroundStyle(.secondary)
            .opacity(0.5)
            .accessibilityLabel("\(link.title), unavailable")
        }
    }
}
