// Views/LoadingStates/SkeletonRow.swift — app_shell bounded context
// DDD role: View — skeleton placeholder rows for cold-load surfaces
// ADR ref: ADR-0031 §"Skeleton loaders"

import SwiftUI

// MARK: - WorkloadListSkeleton

/// Skeleton list rendered while a workload list view is in `.loading` state
/// with no previously loaded rows. Matches the row height of the real
/// `Table` so the cold-load → success transition is jank-free.
///
/// Default 8 rows per ADR-0031 §"Skeleton loaders — Content list".
public struct WorkloadListSkeleton: View {

    private let rowCount: Int

    public init(rowCount: Int = 8) {
        self.rowCount = rowCount
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                WorkloadListSkeletonRow()
                Divider().opacity(0.4)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .shimmering()
    }
}

// MARK: - WorkloadListSkeletonRow

private struct WorkloadListSkeletonRow: View {
    var body: some View {
        HStack(spacing: 16) {
            placeholder(width: 180)
            placeholder(width: 100)
            placeholder(width: 60)
            placeholder(width: 50)
            placeholder(width: 50)
            placeholder(width: 60)
            Spacer()
        }
        .frame(height: 28)
    }

    private func placeholder(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.primary.opacity(0.07))
            .frame(width: width, height: 12)
    }
}

// MARK: - SidebarSkeleton

/// Skeleton placeholder rendered while the sidebar is in `.loading` for the
/// first cluster load. 4 rows per ADR-0031 §"Skeleton loaders — Sidebar".
public struct SidebarSkeleton: View {

    private let rowCount: Int

    public init(rowCount: Int = 4) {
        self.rowCount = rowCount
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { index in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 16, height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: skeletonWidth(for: index), height: 12)
                    Spacer()
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .shimmering()
    }

    private func skeletonWidth(for index: Int) -> CGFloat {
        let widths: [CGFloat] = [140, 110, 160, 90]
        return widths[index % widths.count]
    }
}

// MARK: - DetailHeaderSkeleton

/// Skeleton placeholder rendered while the resource detail drawer header is
/// in `.loading`. Mirrors the final header layout (kind chip + name +
/// namespace badge + status chip) per ADR-0031 §"Skeleton loaders — Detail".
public struct DetailHeaderSkeleton: View {

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                placeholder(width: 60, height: 20, corner: 10)
                placeholder(width: 160, height: 18, corner: 4)
                Spacer()
                placeholder(width: 60, height: 18, corner: 9)
            }
            placeholder(width: 220, height: 12, corner: 4)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .shimmering()
    }

    private func placeholder(width: CGFloat, height: CGFloat, corner: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: corner)
            .fill(Color.primary.opacity(0.08))
            .frame(width: width, height: height)
    }
}
