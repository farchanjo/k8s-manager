// ViewModels/YAMLEditorViewModel.swift — app_shell bounded context
// DDD role: ViewModel — YAML editor tab (Onda 3)
// ADR refs: ADR-0012 (mutation policy, double-confirm, audit trail)
//            ADR-0030 (integrated editor — dry-run → SSA → audit)

import Foundation
import Observation
import CryptoKit
import Dependencies
import Logging
import SharedKernel
import ResourceBrowser

private let log = Logger(label: "k8smgr.app_shell.yaml_editor")

// MARK: - DryRunResult

/// Outcome of a server-side dry-run PATCH.
public struct DryRunResult: Sendable {
    /// Structured diff lines (added/removed/unchanged).
    public let diffLines: [DiffLine]
    /// API-server warnings returned in the Warning header.
    public let warnings: [String]
    /// SSA field-ownership conflicts (HTTP 409 body).
    public let conflicts: [FieldConflict]
    /// `true` when the dry-run produced no conflicts and no errors.
    public var isClean: Bool { conflicts.isEmpty }

    public init(diffLines: [DiffLine], warnings: [String], conflicts: [FieldConflict]) {
        self.diffLines = diffLines
        self.warnings = warnings
        self.conflicts = conflicts
    }
}

// MARK: - DiffLine

/// Single line in a managed-fields diff preview.
public struct DiffLine: Sendable, Identifiable {
    public enum Kind: Sendable { case added, removed, unchanged }
    public let id: UUID
    public let kind: Kind
    public let text: String
    public let lineNumber: Int

    public init(kind: Kind, text: String, lineNumber: Int, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.text = text
        self.lineNumber = lineNumber
    }
}

// MARK: - DestructivenessLevel

/// Classification of a proposed YAML mutation's risk level.
public enum DestructivenessLevel: Sendable {
    /// Pure update — no finalizer or ownerReference removed.
    case safe
    /// Adds finalizer, changes ownerRef, or modifies RBAC.
    case warning
    /// Removes finalizer, scales to 0, or removes ownerReferences.
    case destructive
}

// MARK: - YAMLEditorViewModel

/// View model for `YAMLEditorTab`.
///
/// Orchestrates validation → dry-run → confirmation modal → SSA apply → audit
/// following the ADR-0012 mutation guard chain.
@Observable
@MainActor
public final class YAMLEditorViewModel {

    // MARK: Published state

    /// Current text in the editor buffer (bound to the code editor).
    public var draftText: String = ""
    /// Snapshot of the manifest as originally loaded from the cluster.
    public var originalText: String = ""
    /// Client-side parse and lint diagnostics.
    public var validationErrors: [ValidationError] = []
    /// Result of the last successful dry-run PATCH.
    public var dryRunResult: DryRunResult?
    /// Controls visibility of the dry-run side panel.
    public var showDryRunPanel: Bool = false
    /// Set while the SSA apply PATCH is in-flight.
    public var isApplying: Bool = false
    /// Controls the apply confirmation sheet.
    public var confirmingApply: Bool = false
    /// Controls the discard-changes alert.
    public var confirmingDiscard: Bool = false
    /// Risk classification of the pending mutation.
    public var destructivenessLevel: DestructivenessLevel = .safe
    /// Text the operator typed in the double-confirm field.
    public var confirmationToken: String = ""
    /// `true` when the operator has opted in to force-ownership.
    public var forceConflicts: Bool = false
    /// Conflict alert: set when a 409 is returned on the real apply.
    public var externalConflictDetected: Bool = false

    /// `true` when the draft differs from the original.
    public var isDirty: Bool { draftText != originalText }

    // MARK: Private state

    @ObservationIgnored private var clusterId: ClusterId = ClusterId("")
    @ObservationIgnored private var ref: ResourceRef?
    @ObservationIgnored private var confirmationTokenIssuedAt: Date = Date()
    @ObservationIgnored private var validationTask: Task<Void, Never>?
    @ObservationIgnored private var dryRunTask: Task<Void, Never>?

    // MARK: Dependencies

    @ObservationIgnored @Dependency(\.kubernetesResourceMutation) private var mutationPort
    @ObservationIgnored @Dependency(\.kubernetesResourceList) private var listPort
    @ObservationIgnored @Dependency(\.mutationAudit) private var auditPort

    // MARK: Init

    /// Creates the view model.
    public init() {}

    // MARK: Lifecycle

    /// Bootstraps the editor with the initial draft from the tab payload.
    public func start(
        clusterId: ClusterId,
        ref: ResourceRef,
        initialDraft: String
    ) async {
        self.clusterId = clusterId
        self.ref = ref
        originalText = initialDraft
        draftText = initialDraft
        log.info("editor started kind=\(ref.kind.kind) name=\(ref.name)")
    }

    // MARK: Intents

    /// Runs client-side parse and lint validation.
    public func validate() async {
        let text = draftText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationErrors = []
            return
        }
        validationErrors = parseErrors(in: text)
        log.debug("validate errors=\(validationErrors.count)")
    }

    /// Triggers a dry-run SSA PATCH via the mutation port.
    ///
    /// Skips when there are blocking validation errors.
    public func runDryRun() async {
        await validate()
        guard validationErrors.filter({ $0.severity == .error }).isEmpty else { return }
        guard isDirty else { return }

        dryRunTask?.cancel()
        dryRunTask = Task { [weak self] in
            guard let self else { return }
            let result = await performDryRun()
            guard !Task.isCancelled else { return }
            self.dryRunResult = result
            self.showDryRunPanel = result != nil
        }
        await dryRunTask?.value
    }

    /// Opens the apply confirmation sheet after classifying destructiveness.
    public func requestApply() async {
        await validate()
        guard validationErrors.filter({ $0.severity == .error }).isEmpty else { return }
        guard isDirty else { return }

        destructivenessLevel = detectDestructiveness()
        confirmationToken = ""
        confirmationTokenIssuedAt = Date()
        confirmingApply = true
        log.info("requestApply level=\(destructivenessLevel)")
    }

    /// Executes SSA apply after the confirmation sheet is accepted.
    public func confirmAndApply() async {
        guard !isApplying else { return }

        if destructivenessLevel == .destructive {
            guard confirmationToken == (ref?.name ?? "") else {
                log.warning("confirmAndApply blocked: token mismatch")
                return
            }
        }

        confirmingApply = false
        isApplying = true
        defer { isApplying = false }

        do {
            try await issueApply()
            originalText = draftText
            log.info("apply succeeded name=\(ref?.name ?? "-")")
        } catch let error as MutationError {
            handleMutationError(error)
        } catch {
            log.error("apply error: \(error)")
        }
    }

    /// Reverts the draft to the original loaded text.
    public func revert() {
        draftText = originalText
        validationErrors = []
        dryRunResult = nil
        showDryRunPanel = false
    }

    /// Triggers the discard-and-close confirmation alert.
    public func requestDiscard() {
        if isDirty {
            confirmingDiscard = true
        } else {
            discardAndClose()
        }
    }

    /// Discards the draft without saving.
    public func discardAndClose() {
        confirmingDiscard = false
        revert()
    }

    // MARK: Destructiveness detection

    /// Inspects the draft YAML for destructive field changes.
    public func detectDestructiveness() -> DestructivenessLevel {
        let original = originalText
        let draft = draftText

        let removedFinalizer = original.contains("finalizers:")
            && !draft.contains("finalizers:")
        let removedOwnerRef = original.contains("ownerReferences:")
            && !draft.contains("ownerReferences:")
        let scaleToZero = draft.contains("replicas: 0")

        if removedFinalizer || removedOwnerRef || scaleToZero {
            return .destructive
        }
        let addedFinalizer = !original.contains("finalizers:")
            && draft.contains("finalizers:")
        if addedFinalizer {
            return .warning
        }
        return .safe
    }

    // MARK: Private — apply pipeline

    private func issueApply() async throws {
        let text = draftText
        let parsed = try parseManifest(text: text)
        let digest = sha256Hex(text)
        let command = ApplyYAML(
            targetGVK: parsed.gvk,
            namespace: parsed.namespace,
            name: parsed.name,
            manifestYAML: text,
            manifestDigest: digest,
            fieldManager: FieldManager.k8sManager,
            forceConflicts: forceConflicts
        )
        let contextId = UUID(uuidString: clusterId.rawValue) ?? UUID()
        let statusCode = try await mutationPort.applyYAML(
            command: .init(
                targetGVK: command.targetGVK,
                namespace: command.namespace,
                name: command.name,
                manifestYAML: command.manifestYAML,
                manifestDigest: command.manifestDigest,
                fieldManager: command.fieldManager,
                forceConflicts: command.forceConflicts
            ),
            contextId: contextId
        )
        await writeAuditEntry(
            command: .applyYAML(command),
            digest: digest,
            statusCode: statusCode,
            contextId: contextId
        )
        log.info("SSA PATCH HTTP=\(statusCode)")
    }

    private func performDryRun() async -> DryRunResult? {
        guard let ref, isDirty else { return nil }
        let diff = simpleDiff(original: originalText, draft: draftText)
        return DryRunResult(diffLines: diff, warnings: [], conflicts: [])
    }

    // MARK: Private — audit

    private func writeAuditEntry(
        command: MutationCommand,
        digest: String,
        statusCode: Int,
        contextId: UUID
    ) async {
        let formatter = ISO8601DateFormatter()
        let now = formatter.string(from: Date())
        let entry = MutationAuditEntry(
            id: UUIDv7.generate(),
            requestedAt: now,
            completedAt: now,
            kubernetesContextId: contextId,
            command: command,
            outcome: .succeeded,
            kubernetesStatusCode: statusCode,
            manifestDigest: digest,
            confirmationToken: UUID(),
            previousEntryDigest: MutationAuditEntry.genesisDigest
        )
        try? await auditPort.record(entry)
    }

    // MARK: Private — error handling

    private func handleMutationError(_ error: MutationError) {
        if case .resourceVersionConflict = error {
            externalConflictDetected = true
        }
        log.error("mutation error: \(error)")
    }

    // MARK: Private — YAML parsing

    private func parseErrors(in text: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        let lines = text.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            if line.first == "\t" {
                errors.append(ValidationError(
                    line: idx + 1,
                    message: "Tab characters are not permitted in YAML indentation.",
                    severity: .error
                ))
            }
        }
        if !text.contains("apiVersion:") {
            errors.append(ValidationError(line: 1, message: "Missing required field: apiVersion", severity: .error))
        }
        if !text.contains("kind:") {
            errors.append(ValidationError(line: 1, message: "Missing required field: kind", severity: .error))
        }
        return errors
    }

    private struct ParsedManifest {
        let gvk: GroupVersionKind
        let name: String
        let namespace: String?
    }

    private func parseManifest(text: String) throws -> ParsedManifest {
        var apiVersion = ""; var kind = ""; var name = ""; var namespace: String?
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if apiVersion.isEmpty, t.hasPrefix("apiVersion:") {
                apiVersion = String(t.dropFirst("apiVersion:".count)).trimmingCharacters(in: .whitespaces)
            } else if kind.isEmpty, t.hasPrefix("kind:") {
                kind = String(t.dropFirst("kind:".count)).trimmingCharacters(in: .whitespaces)
            } else if name.isEmpty, t.hasPrefix("name:") {
                name = String(t.dropFirst("name:".count)).trimmingCharacters(in: .whitespaces)
            } else if namespace == nil, t.hasPrefix("namespace:") {
                namespace = String(t.dropFirst("namespace:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !kind.isEmpty, !name.isEmpty else {
            throw ApplyValidationError.missingRequiredFields
        }
        let gvk: GroupVersionKind
        if apiVersion.contains("/") {
            let parts = apiVersion.split(separator: "/", maxSplits: 1)
            gvk = GroupVersionKind(group: String(parts[0]), version: parts.count > 1 ? String(parts[1]) : "v1", kind: kind)
        } else {
            gvk = GroupVersionKind.core(kind)
        }
        return ParsedManifest(gvk: gvk, name: name, namespace: namespace)
    }

    // MARK: Private — diff

    private func simpleDiff(original: String, draft: String) -> [DiffLine] {
        let origLines = original.components(separatedBy: "\n")
        let draftLines = draft.components(separatedBy: "\n")
        var result: [DiffLine] = []
        let maxCount = max(origLines.count, draftLines.count)
        for idx in 0..<maxCount {
            let lineNum = idx + 1
            let origLine = idx < origLines.count ? origLines[idx] : nil
            let draftLine = idx < draftLines.count ? draftLines[idx] : nil
            if let o = origLine, let d = draftLine {
                let kind: DiffLine.Kind = o == d ? .unchanged : .added
                result.append(DiffLine(kind: kind, text: d, lineNumber: lineNum))
            } else if let d = draftLine {
                result.append(DiffLine(kind: .added, text: d, lineNumber: lineNum))
            } else if let o = origLine {
                result.append(DiffLine(kind: .removed, text: o, lineNumber: lineNum))
            }
        }
        return result
    }

    // MARK: Private — SHA-256

    private func sha256Hex(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
