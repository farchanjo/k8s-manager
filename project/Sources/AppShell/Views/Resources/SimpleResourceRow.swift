// Views/Resources/SimpleResourceRow.swift — app_shell bounded context
// DDD role: View — shared row for resource list items (Onda 2)
// ADR ref: ADR-0050 (resource navigation taxonomy)

import SwiftUI
import ResourceBrowser

// MARK: - SimpleResourceRow

/// Generic list row for any `ResourceListItem` showing name, namespace, status and age.
///
/// Used by Network, Storage, RBAC and Cluster list views that project directly
/// from `ResourceListItem` without a dedicated row type.
public struct SimpleResourceRow: View {

    let item: ResourceListItem

    public init(item: ResourceListItem) {
        self.item = item
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.monospaced())
                if let ns = item.namespace {
                    Text(ns).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            StatusBadge(raw: item.status)
            Text(ageLabel(item.ageSeconds))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - SimpleClusterScopedRow

/// List row for cluster-scoped resources (no namespace column).
///
/// Used for ClusterRoles, StorageClasses, CSIDrivers, etc.
public struct SimpleClusterScopedRow: View {

    let item: ResourceListItem
    /// Optional secondary label (e.g. controller, provisioner, driver).
    let secondary: String?

    public init(item: ResourceListItem, secondary: String? = nil) {
        self.item = item
        self.secondary = secondary
    }

    public var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.monospaced())
                if let sec = secondary {
                    Text(sec).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(ageLabel(item.ageSeconds))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Age helper (module-private)

func ageLabel(_ seconds: Int) -> String {
    switch seconds {
    case ..<60:    return "\(seconds)s"
    case ..<3600:  return "\(seconds / 60)m"
    case ..<86400: return "\(seconds / 3600)h"
    default:       return "\(seconds / 86400)d"
    }
}
