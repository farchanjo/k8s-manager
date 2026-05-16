// Views/Detail/Sections/PropertiesSection.swift — app_shell bounded context
// DDD role: View — key-value property grid for a Kubernetes resource
// ADR ref: ADR-0021 (detail drawer — Onda 2)

import SwiftUI
import SharedKernel

// MARK: - PropertiesSection

/// Renders a `Grid`-based key-value table for the `PropertyRow` list
/// produced by `ResourceDetailViewModel`.
///
/// Rows whose `linkedRef` is non-nil render the value as a tappable link
/// that posts a `resourceDetail` tab via the provided `onOpenRef` callback.
@MainActor
public struct PropertiesSection: View {

    public let properties: [PropertyRow]
    /// Called when a linkable value is tapped.
    public let onOpenRef: ((ResourceRef) -> Void)?

    public init(
        properties: [PropertyRow],
        onOpenRef: ((ResourceRef) -> Void)? = nil
    ) {
        self.properties = properties
        self.onOpenRef = onOpenRef
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader
            propertyGrid
        }
    }

    // MARK: Private views

    private var sectionHeader: some View {
        Text("Properties")
            .font(.headline)
            .padding(.bottom, 4)
    }

    private var propertyGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(properties) { row in
                GridRow {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                        .frame(minWidth: 120, alignment: .trailing)

                    propertyValue(row)
                        .gridColumnAlignment(.leading)
                }
                Divider().opacity(0.5)
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func propertyValue(_ row: PropertyRow) -> some View {
        if let ref = row.linkedRef {
            Button {
                onOpenRef?(ref)
            } label: {
                HStack(spacing: 4) {
                    Text(row.value)
                        .font(.subheadline)
                    Image(systemName: "arrow.up.right.square")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Color.accentColor)
        } else {
            Text(row.value)
                .font(.subheadline.monospaced())
                .textSelection(.enabled)
        }
    }
}
