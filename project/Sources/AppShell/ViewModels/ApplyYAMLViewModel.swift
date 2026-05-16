// ViewModels/ApplyYAMLViewModel.swift — app_shell bounded context
// DDD role: ViewModel — YAML/JSON apply tool (kubectl apply -f -)
// ADR ref: ADR-0050 (cluster operations, Onda 2), ADR-0012 (SSA mutation policy)

import Foundation
import Observation
import Dependencies
import Logging
import SharedKernel
import ResourceBrowser

private let log = Logger(label: "k8smgr.app_shell.apply_yaml")

// MARK: - ApplyYAMLViewModel

/// View model for the Apply YAML tab.
///
/// Orchestrates the full user flow: paste / drop YAML → validate →
/// optionally dry-run → server-side apply via `KubernetesResourceMutationPort`.
///
/// All state mutations are `@MainActor`-isolated; `@Observable` drives
/// SwiftUI without `@Published` boilerplate.
@Observable
@MainActor
public final class ApplyYAMLViewModel {

    // MARK: State

    /// The current editor content (YAML or JSON text).
    public var yamlText: String = ""

    /// When `true`, the apply button issues a dry-run request.
    public var dryRun: Bool = false

    /// Namespace override injected into `metadata.namespace` when the manifest
    /// does not declare one. `nil` means no override (use manifest value).
    public var namespaceOverride: String? = nil

    /// Lifecycle state of the most recent apply or dry-run operation.
    public var applyState: AsyncResource<ApplyResult> = .idle

    /// Validation diagnostics produced by `validate()`.
    public var validationErrors: [ValidationError] = []

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.kubernetesResourceMutation) private var mutationPort

    @ObservationIgnored
    private let toastEmitter: any ToastEmitterPort

    // MARK: Init

    /// Creates a view model.
    ///
    /// - Parameter toastEmitter: Port used to emit success / error feedback.
    ///   Defaults to `NoOpToastEmitter` when not supplied (preview / test context).
    public init(toastEmitter: any ToastEmitterPort = NoOpToastEmitter()) {
        self.toastEmitter = toastEmitter
    }

    // MARK: Intents

    /// Runs a client-side parse + lint pass and populates `validationErrors`.
    ///
    /// Does not touch the cluster. The editor calls this on every significant
    /// edit to provide real-time diagnostics.
    public func validate() async {
        validationErrors = await parseAndValidate(text: yamlText)
        log.info("validate errors=\(validationErrors.count)")
    }

    /// Loads the file at `url` into `yamlText`.
    ///
    /// Called by the drop-target handler when the user drops a `.yaml` / `.json`
    /// file onto the editor surface.
    public func dropFile(at url: URL) async {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            yamlText = text
            log.info("dropFile loaded bytes=\(text.utf8.count) path=\(url.lastPathComponent)")
            await validate()
        } catch {
            log.error("dropFile FAILED path=\(url.path) — \(error)")
            validationErrors = [
                ValidationError(
                    line: 1,
                    message: "Could not read file: \(error.localizedDescription)",
                    severity: .error
                )
            ]
        }
    }

    /// Issues a server-side apply (or dry-run) for `yamlText` against `clusterId`.
    ///
    /// Flow:
    /// 1. Client-side validation — aborts when blocking errors exist.
    /// 2. Parses `apiVersion`, `kind`, `metadata.name` from the manifest.
    /// 3. Builds `ApplyYAML` command with `FieldManager.k8sManager`.
    /// 4. Dispatches via `KubernetesResourceMutationPort.applyYAML`.
    /// 5. On success: emits a toast and sets `applyState = .success`.
    /// 6. On failure: populates `applyState = .failure`.
    public func apply(clusterId: ClusterId) async {
        await validate()
        let blocking = validationErrors.filter { $0.severity == .error }
        guard blocking.isEmpty else {
            log.warning("apply blocked by \(blocking.count) validation error(s)")
            return
        }
        applyState = .loading

        do {
            let result = try await performApply(clusterId: clusterId)
            applyState = .success(result)
            await emitSuccessToast(result: result)
            if !dryRun { yamlText = "" }
            log.info("apply OK dryRun=\(dryRun) resources=\(result.appliedResources.count)")
        } catch {
            applyState = .failure(error)
            log.error("apply FAILED — \(error)")
        }
    }

    // MARK: Private — apply pipeline

    private func performApply(clusterId: ClusterId) async throws -> ApplyResult {
        let parsed = try parseManifest(text: yamlText)
        let command = buildCommand(parsed: parsed)
        let contextId = UUID(uuidString: clusterId.rawValue) ?? UUID()
        let statusCode = try await mutationPort.applyYAML(
            command: command,
            contextId: contextId
        )
        log.info("performApply HTTP=\(statusCode)")
        let ref = resourceRef(from: parsed)
        return ApplyResult(
            appliedResources: [ref],
            dryRun: dryRun,
            managedFieldsDiff: dryRun ? "--- dry-run diff placeholder ---" : nil
        )
    }

    private func buildCommand(parsed: ParsedManifest) -> ApplyYAML {
        let ns = namespaceOverride ?? parsed.namespace
        return ApplyYAML(
            targetGVK: parsed.gvk,
            namespace: ns,
            name: parsed.name,
            manifestYAML: yamlText,
            manifestDigest: sha256Stub(yamlText),
            fieldManager: FieldManager.k8sManager,
            forceConflicts: false
        )
    }

    private func resourceRef(from parsed: ParsedManifest) -> ResourceRef {
        let kind = ResourceKind(
            group: parsed.gvk.group,
            version: parsed.gvk.version,
            kind: parsed.gvk.kind
        )
        return ResourceRef(
            kind: kind,
            namespace: namespaceOverride ?? parsed.namespace,
            name: parsed.name
        )
    }

    private func emitSuccessToast(result: ApplyResult) async {
        let names = result.appliedResources.map(\.name).joined(separator: ", ")
        let prefix = result.dryRun ? "Dry-run OK" : "Applied"
        await toastEmitter.emit(
            title: "\(prefix): \(names)",
            message: nil,
            severity: result.dryRun ? .info : .success,
            iconSymbolName: result.dryRun ? "doc.badge.clock" : "checkmark.circle",
            pinned: false,
            action: nil
        )
    }

    // MARK: Private — YAML parsing

    private func parseAndValidate(text: String) async -> [ValidationError] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        var errors: [ValidationError] = []
        if !text.contains("apiVersion:") {
            errors.append(ValidationError(line: 1, message: "Missing required field: apiVersion", severity: .error))
        }
        if !text.contains("kind:") {
            errors.append(ValidationError(line: 1, message: "Missing required field: kind", severity: .error))
        }
        if !text.contains("metadata:") {
            errors.append(ValidationError(line: 1, message: "Missing required field: metadata", severity: .error))
        }
        return errors
    }

    private func parseManifest(text: String) throws -> ParsedManifest {
        // Minimal line-by-line YAML key extraction.
        // Onda 3+ will replace with a real YAML parser dependency.
        var apiVersion = ""
        var kind = ""
        var name = ""
        var namespace: String? = nil

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if apiVersion.isEmpty, trimmed.hasPrefix("apiVersion:") {
                apiVersion = trimmed.dropPrefix("apiVersion:").trimmingCharacters(in: .whitespaces)
            } else if kind.isEmpty, trimmed.hasPrefix("kind:") {
                kind = trimmed.dropPrefix("kind:").trimmingCharacters(in: .whitespaces)
            } else if name.isEmpty, trimmed.hasPrefix("name:") {
                name = trimmed.dropPrefix("name:").trimmingCharacters(in: .whitespaces)
            } else if namespace == nil, trimmed.hasPrefix("namespace:") {
                namespace = trimmed.dropPrefix("namespace:").trimmingCharacters(in: .whitespaces)
            }
        }

        guard !kind.isEmpty, !name.isEmpty else {
            throw ApplyValidationError.missingRequiredFields
        }

        let gvk = groupVersionKind(from: apiVersion, kind: kind)
        return ParsedManifest(gvk: gvk, name: name, namespace: namespace)
    }

    private func groupVersionKind(from apiVersion: String, kind: String) -> GroupVersionKind {
        if apiVersion.contains("/") {
            let parts = apiVersion.split(separator: "/", maxSplits: 1)
            let group = String(parts[0])
            let version = parts.count > 1 ? String(parts[1]) : "v1"
            return GroupVersionKind(group: group, version: version, kind: kind)
        }
        return GroupVersionKind.core(kind)
    }

    /// Stub digest — Onda 3+ replaces with `CryptoKit.SHA256`.
    private func sha256Stub(_ text: String) -> String {
        String(abs(text.hashValue), radix: 16)
    }
}

// MARK: - ApplyValidationError

/// Errors thrown by the manifest parse step inside `ApplyYAMLViewModel`.
public enum ApplyValidationError: Error, Sendable {
    /// `kind` or `metadata.name` could not be extracted from the manifest.
    case missingRequiredFields
}

// MARK: - ParsedManifest (private transport)

private struct ParsedManifest {
    let gvk: GroupVersionKind
    let name: String
    let namespace: String?
}

// MARK: - NoOpToastEmitter

/// Silent toast emitter used as the default in previews and tests.
public struct NoOpToastEmitter: ToastEmitterPort, Sendable {
    public init() {}
    public func emit(
        title: String, message: String?, severity: ToastDomainSeverity,
        iconSymbolName: String?, pinned: Bool, action: ToastDomainAction?
    ) async {}
}

// MARK: - String helper

private extension String {
    func dropPrefix(_ prefix: String) -> Substring {
        guard hasPrefix(prefix) else { return self[startIndex...] }
        return self[index(startIndex, offsetBy: prefix.count)...]
    }
}
