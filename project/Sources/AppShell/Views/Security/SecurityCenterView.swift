// Views/Security/SecurityCenterView.swift — app_shell bounded context
// DDD role: View — Security Center coordinator (ADR-0068)
// ADR ref: ADR-0068 (Security Center sidebar surface and content)

import SwiftUI
import SharedKernel

// MARK: - SecurityCenterView

/// Coordinator view for the Security Center section.
///
/// Renders a landing overview card listing the four sub-entries defined in
/// ADR-0068 (Overview, Images, Resources, Roles), with a brief description
/// of each. Operators navigate to individual sub-entry views via the sidebar
/// tree; this view is shown when the "Security Center" header is activated.
///
/// Per ADR-0068 §"Chosen option A" rationale: the section header toggles the
/// disclosure group; activating a sub-entry renders the view directly in the
/// content area. `SecurityCenterView` acts as the fall-through when the
/// header itself is tapped without a sub-entry selected.
@MainActor
public struct SecurityCenterView: View {

    // MARK: Properties

    public let clusterId: ClusterId

    public init(clusterId: ClusterId) {
        self.clusterId = clusterId
    }

    // MARK: Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                subEntryCards
                footerNote
            }
            .padding(20)
        }
        .navigationTitle("Security Center")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Security Center landing page")
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Security Center")
                    .font(.title2.bold())
            }
            Text("Read-only security posture for cluster \(clusterId.rawValue).")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Data sourced exclusively from the Kubernetes API. External scanner integration is planned for a future release.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Sub-entry cards

    private var subEntryCards: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 16
        ) {
            SecurityCenterCard(
                title: "Overview",
                description: "Cluster-wide security posture: pods running as root, namespaces missing PSA labels, network policy count, and mTLS-protected services.",
                icon: "chart.bar.xaxis",
                color: .blue
            )
            SecurityCenterCard(
                title: "Images",
                description: "Per-image inventory of running containers: digest presence, distroless detection, and imagePullSecret bindings.",
                icon: "photo.stack",
                color: .purple
            )
            SecurityCenterCard(
                title: "Resources",
                description: "Pods breaching security baselines: privileged containers, host network, missing resource limits and probes.",
                icon: "exclamationmark.shield",
                color: .orange
            )
            SecurityCenterCard(
                title: "Roles",
                description: "RBAC privilege audit: ClusterRoles and Roles sorted by privilege level, wildcard verbs, and subject counts.",
                icon: "person.badge.key",
                color: .red
            )
        }
    }

    // MARK: Footer

    private var footerNote: some View {
        Text("Select a sub-entry in the sidebar to drill down into each view.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }
}

// MARK: - SecurityCenterCard

/// Information card for a single Security Center sub-entry.
private struct SecurityCenterCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(color)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.headline)
                }
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}
