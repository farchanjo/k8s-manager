// Views/Detail/Sections/ContainersSection.swift — app_shell bounded context
// DDD role: View — per-container row list for the detail drawer
// ADR ref: ADR-0021 (detail drawer — Onda 2)

import SwiftUI
import SharedKernel

// MARK: - ContainersSection

/// Lists one row per container belonging to a Pod resource.
///
/// Each row shows: container name, image reference, state badge, ready
/// indicator, and shortcut buttons for Logs and Exec.
@MainActor
public struct ContainersSection: View {

    public let containers: [ContainerRow]
    /// Called when the user opens a logs tab for a container.
    public let onLogs: ((String) -> Void)?
    /// Called when the user opens an exec/shell tab for a container.
    public let onExec: ((String) -> Void)?

    public init(
        containers: [ContainerRow],
        onLogs: ((String) -> Void)? = nil,
        onExec: ((String) -> Void)? = nil
    ) {
        self.containers = containers
        self.onLogs = onLogs
        self.onExec = onExec
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader
            containerList
        }
    }

    // MARK: Private views

    private var sectionHeader: some View {
        Text("Containers (\(containers.count))")
            .font(.headline)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var containerList: some View {
        if containers.isEmpty {
            Text("No containers — only available for Pods.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
        } else {
            VStack(spacing: 1) {
                ForEach(containers) { container in
                    containerRow(container)
                }
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func containerRow(_ container: ContainerRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "cube")
                .imageScale(.small)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.id)
                    .font(.subheadline.weight(.medium))
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            stateBadge(container)
            readyBadge(container.ready)

            actionButtons(for: container)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stateBadge(_ container: ContainerRow) -> some View {
        let color: Color = container.state.lowercased() == "running" ? .green : .orange
        return Text(container.state)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func readyBadge(_ ready: Bool) -> some View {
        Image(systemName: ready ? "checkmark.circle.fill" : "circle")
            .imageScale(.small)
            .foregroundStyle(ready ? Color.green : Color.secondary)
            .help(ready ? "Ready" : "Not ready")
    }

    private func actionButtons(for container: ContainerRow) -> some View {
        HStack(spacing: 2) {
            Button { onLogs?(container.id) } label: {
                Image(systemName: "text.alignleft")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("Logs")

            Button { onExec?(container.id) } label: {
                Image(systemName: "terminal")
                    .imageScale(.small)
            }
            .buttonStyle(.borderless)
            .help("Exec")
        }
    }
}
