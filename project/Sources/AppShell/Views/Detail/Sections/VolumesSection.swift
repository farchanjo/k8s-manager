// Views/Detail/Sections/VolumesSection.swift — app_shell bounded context
// DDD role: View — mounted volume list for the detail drawer
// ADR ref: ADR-0021 (detail drawer — Onda 2)

import SwiftUI

// MARK: - VolumesSection

/// Lists volume mounts declared in a Pod spec.
///
/// Columns: name, type badge, source identifier.
/// For non-Pod resources or when volume extraction is not yet implemented,
/// a placeholder is shown.
@MainActor
public struct VolumesSection: View {

    public let volumes: [VolumeRow]

    public init(volumes: [VolumeRow]) {
        self.volumes = volumes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader
            volumeList
        }
    }

    // MARK: Private views

    private var sectionHeader: some View {
        Text("Volumes (\(volumes.count))")
            .font(.headline)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private var volumeList: some View {
        if volumes.isEmpty {
            Text("No volumes — only available for Pods.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
        } else {
            VStack(spacing: 1) {
                ForEach(volumes) { volume in
                    volumeRow(volume)
                }
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func volumeRow(_ volume: VolumeRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: volumeIcon(type: volume.volumeType))
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(volume.id)
                .font(.subheadline.weight(.medium))

            Spacer()

            typeBadge(volume.volumeType)

            Text(volume.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func typeBadge(_ type: String) -> some View {
        Text(type)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private func volumeIcon(type: String) -> String {
        switch type.lowercased() {
        case "pvc":                  return "cylinder"
        case "configmap":            return "doc.text"
        case "secret":               return "lock.doc"
        case "emptydir", "emptydir": return "folder.badge.gearshape"
        case "hostpath":             return "externaldrive"
        default:                     return "square.stack.3d.up"
        }
    }
}
