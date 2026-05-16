// Views/Chips/NodeConditionBadge.swift — app_shell bounded context
// DDD role: View
// ADR ref: ADR-0062 (status chips and node conditions)

import SwiftUI

// MARK: - NodeConditionInput

/// Raw input required to compute chips for a single node.
///
/// Callers populate this from `node.status.conditions` and `node.spec.unschedulable`.
public struct NodeConditionInput: Sendable, Hashable {

    /// A single raw condition entry from `node.status.conditions`.
    public struct Condition: Sendable, Hashable {
        /// Condition type string (e.g., `"Ready"`, `"MemoryPressure"`).
        public let type: String
        /// Condition status (`"True"`, `"False"`, `"Unknown"`).
        public let status: String
        /// Human-readable condition message from the kubelet.
        public let message: String?

        public init(type: String, status: String, message: String? = nil) {
            self.type = type
            self.status = status
            self.message = message
        }
    }

    /// All conditions reported for this node.
    public let conditions: [Condition]
    /// `true` when `node.spec.unschedulable == true` or the unschedulable taint is present.
    public let isUnschedulable: Bool

    public init(conditions: [Condition], isUnschedulable: Bool = false) {
        self.conditions = conditions
        self.isUnschedulable = isUnschedulable
    }
}

// MARK: - NodeConditionBadge

/// Renders the worst-severity chip for a node in a list row, plus a tooltip from the
/// raw condition message.
///
/// In the list row only the single highest-severity chip is shown (ADR-0062 compaction rule).
/// For the detail drawer, enumerate `resolvedChips` directly and render each chip individually.
///
/// Usage:
/// ```swift
/// NodeConditionBadge(input: NodeConditionInput(
///     conditions: [.init(type: "Ready", status: "True", message: "kubelet is healthy")],
///     isUnschedulable: false
/// ))
/// ```
public struct NodeConditionBadge: View {

    private let input: NodeConditionInput

    public init(input: NodeConditionInput) {
        self.input = input
    }

    /// Convenience initialiser for the common case where only the raw status string is known.
    ///
    /// Synthesises a single `Ready` condition from the string. Use this to migrate
    /// call sites that previously passed `row.status` to `StatusBadge(raw:)`.
    public init(rawStatus: String) {
        self.input = NodeConditionInput(
            conditions: [.init(type: "Ready", status: rawStatus)],
            isUnschedulable: false
        )
    }

    public var body: some View {
        if let chip = worstChip {
            StatusChip(variant: chip.variant, label: chip.label, tooltip: chip.tooltip)
        }
    }

    // MARK: Private helpers

    /// All non-suppressed chips resolved from the input conditions.
    var resolvedChips: [NodeConditionChip] {
        var chips: [NodeConditionChip] = []

        for condition in input.conditions {
            switch condition.type {
            case "Ready":
                chips.append(
                    StatusChipSemantic.readyChip(status: condition.status, message: condition.message)
                )
            case "MemoryPressure", "DiskPressure", "PIDPressure":
                if let chip = StatusChipSemantic.pressureChip(
                    type: condition.type,
                    status: condition.status,
                    message: condition.message
                ) {
                    chips.append(chip)
                }
            case "NetworkUnavailable":
                if let chip = StatusChipSemantic.networkUnavailableChip(
                    status: condition.status,
                    message: condition.message
                ) {
                    chips.append(chip)
                }
            default:
                break
            }
        }

        if let chip = StatusChipSemantic.schedulingDisabledChip(isUnschedulable: input.isUnschedulable) {
            chips.append(chip)
        }

        return chips
    }

    private var worstChip: NodeConditionChip? {
        StatusChipSemantic.worstChip(from: resolvedChips)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Node conditions") {
    VStack(alignment: .leading, spacing: 8) {
        NodeConditionBadge(input: .init(
            conditions: [.init(type: "Ready", status: "True", message: "kubelet is healthy")],
            isUnschedulable: false
        ))
        NodeConditionBadge(input: .init(
            conditions: [.init(type: "Ready", status: "False", message: "node lost contact")],
            isUnschedulable: false
        ))
        NodeConditionBadge(input: .init(
            conditions: [
                .init(type: "Ready", status: "True"),
                .init(type: "MemoryPressure", status: "True", message: "memory available: 10Mi"),
            ],
            isUnschedulable: false
        ))
        NodeConditionBadge(input: .init(
            conditions: [.init(type: "Ready", status: "True")],
            isUnschedulable: true
        ))
    }
    .padding()
}
#endif
