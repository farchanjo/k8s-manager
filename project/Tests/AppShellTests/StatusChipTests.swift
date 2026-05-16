// Tests/AppShellTests/StatusChipTests.swift
// Coverage: StatusChipSemantic mapping rules per ADR-0062; edge cases and severity compaction.

import XCTest
@testable import AppShell

// MARK: - StatusChipVariantTests

final class StatusChipVariantTests: XCTestCase {

    // MARK: severityRank order

    func test_severityRank_errorHighestNeutralLowest() {
        XCTAssertGreaterThan(StatusChipVariant.error.severityRank,   StatusChipVariant.warning.severityRank)
        XCTAssertGreaterThan(StatusChipVariant.warning.severityRank, StatusChipVariant.success.severityRank)
        XCTAssertGreaterThan(StatusChipVariant.success.severityRank, StatusChipVariant.info.severityRank)
        XCTAssertGreaterThan(StatusChipVariant.info.severityRank,    StatusChipVariant.neutral.severityRank)
    }

    // MARK: systemImage uniqueness (each icon is distinct)

    func test_systemImage_allVariantsHaveNonEmptyIcon() {
        for variant in StatusChipVariant.allCases {
            XCTAssertFalse(variant.systemImage.isEmpty, "variant \(variant) has empty systemImage")
        }
    }

    func test_systemImage_successIsCheckmark() {
        XCTAssertEqual(StatusChipVariant.success.systemImage, "checkmark.circle.fill")
    }

    func test_systemImage_warningIsTriangle() {
        XCTAssertEqual(StatusChipVariant.warning.systemImage, "exclamationmark.triangle.fill")
    }

    func test_systemImage_errorIsXmark() {
        XCTAssertEqual(StatusChipVariant.error.systemImage, "xmark.circle.fill")
    }
}

// MARK: - NodeConditionStatusTests

final class NodeConditionStatusTests: XCTestCase {

    func test_from_recognisedValues() {
        XCTAssertEqual(NodeConditionStatus.from(raw: "True"),    .true)
        XCTAssertEqual(NodeConditionStatus.from(raw: "False"),   .false)
        XCTAssertEqual(NodeConditionStatus.from(raw: "Unknown"), .unknown)
    }

    func test_from_unrecognisedValueDefaultsToUnknown() {
        XCTAssertEqual(NodeConditionStatus.from(raw: ""),         .unknown)
        XCTAssertEqual(NodeConditionStatus.from(raw: "true"),     .unknown) // case-sensitive
        XCTAssertEqual(NodeConditionStatus.from(raw: "whatever"), .unknown)
    }
}

// MARK: - StatusChipSemanticReadyTests

final class StatusChipSemanticReadyTests: XCTestCase {

    func test_readyChip_trueStatusIsSuccess() {
        let chip = StatusChipSemantic.readyChip(status: "True", message: "ok")
        XCTAssertEqual(chip.variant, .success)
        XCTAssertEqual(chip.label, "Ready")
        XCTAssertEqual(chip.tooltip, "ok")
    }

    func test_readyChip_falseStatusIsError() {
        let chip = StatusChipSemantic.readyChip(status: "False")
        XCTAssertEqual(chip.variant, .error)
        XCTAssertEqual(chip.label, "NotReady")
        XCTAssertNil(chip.tooltip)
    }

    func test_readyChip_unknownStatusIsWarning() {
        let chip = StatusChipSemantic.readyChip(status: "Unknown")
        XCTAssertEqual(chip.variant, .warning)
        XCTAssertEqual(chip.label, "Unknown")
    }

    func test_readyChip_unrecognisedStatusTreatedAsUnknown() {
        let chip = StatusChipSemantic.readyChip(status: "")
        XCTAssertEqual(chip.variant, .warning)
    }
}

// MARK: - StatusChipSemanticPressureTests

final class StatusChipSemanticPressureTests: XCTestCase {

    private let pressureTypes = ["MemoryPressure", "DiskPressure", "PIDPressure"]

    func test_pressureChip_trueStatusIsError() {
        for type in pressureTypes {
            let chip = StatusChipSemantic.pressureChip(type: type, status: "True", message: "high")
            XCTAssertEqual(chip?.variant, .error, "type=\(type)")
            XCTAssertEqual(chip?.label, type, "label mismatch for \(type)")
            XCTAssertEqual(chip?.tooltip, "high")
        }
    }

    func test_pressureChip_falseStatusSuppressesChip() {
        for type in pressureTypes {
            let chip = StatusChipSemantic.pressureChip(type: type, status: "False")
            XCTAssertNil(chip, "type=\(type) should be suppressed")
        }
    }

    func test_pressureChip_unknownStatusIsWarning() {
        for type in pressureTypes {
            let chip = StatusChipSemantic.pressureChip(type: type, status: "Unknown")
            XCTAssertEqual(chip?.variant, .warning, "type=\(type)")
            XCTAssertEqual(chip?.label, type)
        }
    }
}

// MARK: - StatusChipSemanticNetworkTests

final class StatusChipSemanticNetworkTests: XCTestCase {

    func test_networkUnavailableChip_trueIsError() {
        let chip = StatusChipSemantic.networkUnavailableChip(status: "True", message: "cni not ready")
        XCTAssertEqual(chip?.variant, .error)
        XCTAssertEqual(chip?.label, "NetworkUnavailable")
        XCTAssertEqual(chip?.tooltip, "cni not ready")
    }

    func test_networkUnavailableChip_falseIsSuppressed() {
        let chip = StatusChipSemantic.networkUnavailableChip(status: "False")
        XCTAssertNil(chip)
    }

    func test_networkUnavailableChip_unknownIsWarning() {
        let chip = StatusChipSemantic.networkUnavailableChip(status: "Unknown")
        XCTAssertEqual(chip?.variant, .warning)
    }
}

// MARK: - StatusChipSemanticSchedulingTests

final class StatusChipSemanticSchedulingTests: XCTestCase {

    func test_schedulingDisabledChip_trueReturnsWarning() {
        let chip = StatusChipSemantic.schedulingDisabledChip(isUnschedulable: true)
        XCTAssertEqual(chip?.variant, .warning)
        XCTAssertEqual(chip?.label, "SchedulingDisabled")
    }

    func test_schedulingDisabledChip_falseIsSuppressed() {
        let chip = StatusChipSemantic.schedulingDisabledChip(isUnschedulable: false)
        XCTAssertNil(chip)
    }
}

// MARK: - StatusChipSemanticPodPhaseTests

final class StatusChipSemanticPodPhaseTests: XCTestCase {

    func test_podPhaseChip_runningAllReadyIsSuccess() {
        let chip = StatusChipSemantic.podPhaseChip(
            phase: "Running", allContainersReady: true, hasCrashLoopBackOff: false
        )
        XCTAssertEqual(chip.variant, .success)
        XCTAssertEqual(chip.label, "Running")
    }

    func test_podPhaseChip_runningNotAllReadyIsDegraded() {
        let chip = StatusChipSemantic.podPhaseChip(
            phase: "Running", allContainersReady: false, hasCrashLoopBackOff: false
        )
        XCTAssertEqual(chip.variant, .warning)
        XCTAssertEqual(chip.label, "Degraded")
    }

    func test_podPhaseChip_pendingIsWarning() {
        let chip = StatusChipSemantic.podPhaseChip(phase: "Pending")
        XCTAssertEqual(chip.variant, .warning)
        XCTAssertEqual(chip.label, "Pending")
    }

    func test_podPhaseChip_failedIsError() {
        let chip = StatusChipSemantic.podPhaseChip(phase: "Failed")
        XCTAssertEqual(chip.variant, .error)
        XCTAssertEqual(chip.label, "Failed")
    }

    func test_podPhaseChip_succeededIsNeutral() {
        let chip = StatusChipSemantic.podPhaseChip(phase: "Succeeded")
        XCTAssertEqual(chip.variant, .neutral)
        XCTAssertEqual(chip.label, "Succeeded")
    }

    func test_podPhaseChip_unknownPhaseIsWarning() {
        let chip = StatusChipSemantic.podPhaseChip(phase: "Unknown")
        XCTAssertEqual(chip.variant, .warning)
        XCTAssertEqual(chip.label, "Unknown")
    }

    func test_podPhaseChip_emptyPhaseIsWarning() {
        let chip = StatusChipSemantic.podPhaseChip(phase: "")
        XCTAssertEqual(chip.variant, .warning)
        XCTAssertEqual(chip.label, "Unknown")
    }

    func test_podPhaseChip_crashLoopBackOffOverridesPhase() {
        let chip = StatusChipSemantic.podPhaseChip(
            phase: "Running",
            allContainersReady: true,
            hasCrashLoopBackOff: true,
            message: "back-off restarting failed container"
        )
        XCTAssertEqual(chip.variant, .error)
        XCTAssertEqual(chip.label, "CrashLoopBackOff")
        XCTAssertEqual(chip.tooltip, "back-off restarting failed container")
    }
}

// MARK: - StatusChipSemanticWorstChipTests

final class StatusChipSemanticWorstChipTests: XCTestCase {

    func test_worstChip_emptyCollectionIsNil() {
        XCTAssertNil(StatusChipSemantic.worstChip(from: []))
    }

    func test_worstChip_singleElementReturnsThatElement() {
        let chip = NodeConditionChip(variant: .success, label: "Ready")
        XCTAssertEqual(StatusChipSemantic.worstChip(from: [chip]), chip)
    }

    func test_worstChip_errorBeatsAllOthers() {
        let chips = [
            NodeConditionChip(variant: .success, label: "Ready"),
            NodeConditionChip(variant: .error,   label: "MemoryPressure"),
            NodeConditionChip(variant: .warning, label: "DiskPressure"),
        ]
        XCTAssertEqual(StatusChipSemantic.worstChip(from: chips)?.variant, .error)
    }

    func test_worstChip_warningBeatsSuccessAndNeutral() {
        let chips = [
            NodeConditionChip(variant: .success, label: "Ready"),
            NodeConditionChip(variant: .warning, label: "SchedulingDisabled"),
            NodeConditionChip(variant: .neutral, label: "Succeeded"),
        ]
        XCTAssertEqual(StatusChipSemantic.worstChip(from: chips)?.variant, .warning)
    }

    func test_worstChip_allSuccessReturnsSingle() {
        let chips = [NodeConditionChip(variant: .success, label: "Ready")]
        XCTAssertEqual(StatusChipSemantic.worstChip(from: chips)?.label, "Ready")
    }
}

// MARK: - NodeConditionBadgeResolvedChipsTests

@MainActor
final class NodeConditionBadgeResolvedChipsTests: XCTestCase {

    func test_resolvedChips_readyTrueOnlyReturnsOneSuccessChip() {
        let sut = NodeConditionBadge(input: .init(
            conditions: [.init(type: "Ready", status: "True", message: "ok")],
            isUnschedulable: false
        ))
        let chips = sut.resolvedChips
        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(chips[0].variant, .success)
        XCTAssertEqual(chips[0].label, "Ready")
    }

    func test_resolvedChips_memoryPressureTrueAddsErrorChip() {
        let sut = NodeConditionBadge(input: .init(
            conditions: [
                .init(type: "Ready",          status: "True"),
                .init(type: "MemoryPressure", status: "True", message: "low memory"),
            ],
            isUnschedulable: false
        ))
        let chips = sut.resolvedChips
        XCTAssertEqual(chips.count, 2)
        XCTAssertTrue(chips.contains { $0.variant == .error && $0.label == "MemoryPressure" })
    }

    func test_resolvedChips_unschedulableAddsWarningChip() {
        let sut = NodeConditionBadge(input: .init(
            conditions: [.init(type: "Ready", status: "True")],
            isUnschedulable: true
        ))
        let chips = sut.resolvedChips
        XCTAssertTrue(chips.contains { $0.label == "SchedulingDisabled" })
    }

    func test_resolvedChips_unknownConditionTypeIsIgnored() {
        let sut = NodeConditionBadge(input: .init(
            conditions: [.init(type: "CustomCondition", status: "True")],
            isUnschedulable: false
        ))
        XCTAssertTrue(sut.resolvedChips.isEmpty)
    }

    func test_resolvedChips_networkUnavailableFalseIsSuppressed() {
        let sut = NodeConditionBadge(input: .init(
            conditions: [
                .init(type: "Ready",              status: "True"),
                .init(type: "NetworkUnavailable", status: "False"),
            ],
            isUnschedulable: false
        ))
        let chips = sut.resolvedChips
        XCTAssertFalse(chips.contains { $0.label == "NetworkUnavailable" })
    }

    func test_resolvedChips_emptyConditionsAndNotUnschedulableIsEmpty() {
        let sut = NodeConditionBadge(input: .init(conditions: [], isUnschedulable: false))
        XCTAssertTrue(sut.resolvedChips.isEmpty)
    }

    // MARK: rawStatus convenience init

    func test_rawStatusInit_readyMapsToSuccessChip() {
        let sut = NodeConditionBadge(rawStatus: "True")
        XCTAssertEqual(sut.resolvedChips.first?.variant, .success)
    }

    func test_rawStatusInit_notReadyMapsToErrorChip() {
        let sut = NodeConditionBadge(rawStatus: "False")
        XCTAssertEqual(sut.resolvedChips.first?.variant, .error)
    }
}
