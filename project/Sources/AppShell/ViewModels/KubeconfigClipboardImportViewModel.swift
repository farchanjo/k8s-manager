// ViewModels/KubeconfigClipboardImportViewModel.swift — app_shell bounded context
// DDD role: View model — kubeconfig clipboard-paste import sheet
// ADR ref: ADR-0056 (kubeconfig import from clipboard)

import AppKit
import ClusterConnectivity
import Foundation
import Logging
import Observation

// MARK: - ClipboardImportState

/// Phase model for the clipboard-paste import sheet (ADR-0056 § "Validation sheet UI shape").
public enum ClipboardImportState: Sendable {
    /// No pasteboard read has been attempted yet.
    case idle
    /// A pasteboard read is in progress; indeterminate progress indicator shown.
    case parsing
    /// Pasteboard was empty or contained no plain-text value.
    case emptyClipboard
    /// YAML parse or structural validation failed. `violations` is a non-empty list
    /// of error descriptions to render as callout items.
    case invalid(violations: [String])
    /// Parse and structural validation passed. Ready for the operator to confirm.
    case valid(summary: ImportSummary)
    /// Import is in progress after the operator pressed "Import".
    case importing
    /// Import completed successfully.
    case imported(clusterCount: Int)
    /// Import failed after successful validation; e.g., a port error.
    case importFailed(detail: String)
}

// MARK: - ImportSummary

/// Summary table shown after successful validation (ADR-0056 § step 7 of the import contract).
public struct ImportSummary: Sendable {
    /// Number of cluster entries in the parsed kubeconfig.
    public let clusterCount: Int
    /// Number of context entries in the parsed kubeconfig.
    public let contextCount: Int
    /// Value of `current-context` in the pasted YAML, if present.
    public let currentContext: String?
    /// Provider hints per cluster name, derived from the exec-block command.
    public let providerHints: [String: String]
    /// The successfully parsed kubeconfig, held for the import call.
    public let kubeconfig: Kubeconfig
}

// MARK: - KubeconfigClipboardImportViewModel

/// Observable view model driving the clipboard-paste kubeconfig import sheet.
///
/// Reads the system clipboard, delegates YAML parsing to `KubeconfigLoaderPort`,
/// runs structural validation, and on confirmation calls `importHandler` with
/// the parsed `Kubeconfig`. Security contract (ADR-0056 § "Security note"):
/// raw YAML, bearer tokens, and PEM blocks are never logged.
@Observable
@MainActor
public final class KubeconfigClipboardImportViewModel {

    // MARK: Published state

    /// Current phase of the import flow.
    public private(set) var state: ClipboardImportState = .idle

    // MARK: Dependencies

    private let loader: any KubeconfigLoaderPort
    private let importHandler: (@MainActor (Kubeconfig) async throws -> Void)?
    private let logger: Logger

    // MARK: Init

    /// Designated initialiser.
    ///
    /// - Parameters:
    ///   - loader: Port used to parse the clipboard YAML string (ADR-0056: reuses
    ///     `YamsKubeconfigAdapter` via the port interface).
    ///   - importHandler: Called with the validated `Kubeconfig` when the operator
    ///     presses "Import". The handler is responsible for merging the entries into
    ///     the per-cluster store (ADR-0026). `nil` = no-op (useful for previews).
    ///   - logger: Structured logger. Only cluster names and success/failure
    ///     booleans are logged; no credential material is emitted.
    public init(
        loader: any KubeconfigLoaderPort,
        importHandler: (@MainActor (Kubeconfig) async throws -> Void)? = nil,
        logger: Logger = Logger(label: "kubeconfig.clipboard-import")
    ) {
        self.loader = loader
        self.importHandler = importHandler
        self.logger = logger
    }

    // MARK: Actions

    /// Reads `NSPasteboard.general`, parses the YAML, and runs structural validation.
    ///
    /// Transitions `state` through `.parsing` → `.emptyClipboard`, `.invalid`, or `.valid`.
    public func pasteFromClipboard() {
        state = .parsing
        Task {
            await performParseAndValidate()
        }
    }

    /// Triggers the import by calling `importHandler` with the validated `Kubeconfig`.
    ///
    /// No-op unless `state == .valid(_)`. Transitions through `.importing` → `.imported`
    /// or `.importFailed`.
    public func confirmImport() {
        guard case .valid(let summary) = state else { return }
        state = .importing
        Task {
            await performImport(kubeconfig: summary.kubeconfig, clusterCount: summary.clusterCount)
        }
    }

    /// Resets `state` to `.idle`, discarding any validated content.
    public func cancel() {
        state = .idle
    }

    // MARK: Private — parse and validate

    private func performParseAndValidate() async {
        guard let yamlText = NSPasteboard.general.string(forType: .string),
              !yamlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .emptyClipboard
            return
        }

        let parsed: Kubeconfig
        do {
            parsed = try await loader.parse(yaml: yamlText)
        } catch {
            // Log only the error description — never the YAML content itself.
            logger.warning("Clipboard kubeconfig parse failed", metadata: [
                "error": "\(error)"
            ])
            let detail: String
            if case KubeconfigLoadError.parseError(let d) = error { detail = d }
            else { detail = error.localizedDescription }
            state = .invalid(violations: [detail])
            return
        }

        let violations = structuralValidation(parsed)
        if !violations.isEmpty {
            state = .invalid(violations: violations)
            return
        }

        let summary = ImportSummary(
            clusterCount: parsed.clusters.count,
            contextCount: parsed.contexts.count,
            currentContext: parsed.currentContext,
            providerHints: deriveProviderHints(from: parsed),
            kubeconfig: parsed
        )
        state = .valid(summary: summary)
    }

    // MARK: Private — structural validation (ADR-0056 § step 5)

    private func structuralValidation(_ config: Kubeconfig) -> [String] {
        var violations: [String] = []

        if config.contexts.isEmpty {
            violations.append("contexts[] is empty — at least one context is required.")
        }

        let clusterNames = Set(config.clusters.map(\.name))
        let userNames = Set(config.users.map(\.name))

        for ctx in config.contexts {
            if !clusterNames.contains(ctx.cluster) {
                violations.append(
                    "Context '\(ctx.name)' references unknown cluster '\(ctx.cluster)'."
                )
            }
            if !userNames.contains(ctx.user) {
                violations.append(
                    "Context '\(ctx.name)' references unknown user '\(ctx.user)'."
                )
            }
        }

        for cluster in config.clusters {
            let server = cluster.server
            guard !server.isEmpty,
                  let url = URL(string: server),
                  url.scheme == "https" || url.scheme == "http" else {
                violations.append(
                    "Cluster '\(cluster.name)' has an invalid server URL: '\(server)'."
                )
                continue
            }
        }

        for user in config.users {
            if let exec = user.exec, exec.command.isEmpty {
                violations.append(
                    "User '\(user.name)' has an exec block with an empty 'command' field."
                )
            }
        }

        return violations
    }

    // MARK: Private — provider hint derivation (ADR-0056 § step 7)

    /// Maps exec-block command patterns to operator-facing provider labels.
    private func deriveProviderHints(from config: Kubeconfig) -> [String: String] {
        var hints: [String: String] = [:]
        for ctx in config.contexts {
            guard let user = config.users.first(where: { $0.name == ctx.user }) else {
                hints[ctx.name] = "Local"
                continue
            }
            hints[ctx.name] = providerLabel(for: user.exec?.command)
        }
        return hints
    }

    private func providerLabel(for command: String?) -> String {
        switch command {
        case "aws":         return "AWS EKS"
        case "kubelogin":   return "Azure AKS"
        case "gcloud", "gke-gcloud-auth-plugin": return "GCP GKE"
        case let c? where c.contains("oidc"): return "OIDC"
        case .some: return "Custom exec"
        case .none: return "Local"
        }
    }

    // MARK: Private — import

    private func performImport(kubeconfig: Kubeconfig, clusterCount: Int) async {
        do {
            try await importHandler?(kubeconfig)
            logger.info("Clipboard kubeconfig imported", metadata: [
                "clusterCount": "\(clusterCount)"
            ])
            state = .imported(clusterCount: clusterCount)
        } catch {
            logger.error("Clipboard kubeconfig import failed", metadata: [
                "error": "\(error)"
            ])
            state = .importFailed(detail: error.localizedDescription)
        }
    }
}
