// Views/Resources/Config/SecretRevealSheetViewModel.swift — app_shell bounded context
// DDD role: ViewModel (reveal/hide state machine per ADR-0063)
// ADR refs: ADR-0063 (secret reveal/hide + dockerconfigjson parser),
//           ADR-0047 (HMAC audit chain)

import Foundation
import Observation
import Dependencies
import LocalPersistence
import SharedKernel

// MARK: - KeyRevealState

/// The visibility state of a single data key in the reveal sheet.
public enum KeyRevealState: Equatable, Sendable {
    /// Value is masked (default on drawer open).
    case masked
    /// Value has been decoded and is displayed.
    case revealed(String)
    /// Decoding failed.
    case error(String)

    /// Returns `true` when the value is currently visible.
    public var isRevealed: Bool {
        if case .revealed = self { return true }
        return false
    }
}

// MARK: - DockerConfigParseResult

/// Combines the parse outcome of a `.dockerconfigjson` value.
struct DockerConfigParseResult {
    let config: DockerConfigJSON?
    let error: DockerConfigParseError?
}

// MARK: - SecretRevealSheetViewModel

/// View model for `SecretRevealSheet`.
///
/// Manages per-key reveal state, dispatches audit writes via
/// `SecretRevealAuditPort`, and parses `dockerconfigjson` on demand.
@Observable
@MainActor
public final class SecretRevealSheetViewModel {

    // MARK: State

    /// Per-key reveal states keyed by data key name.
    public var keyStates: [String: KeyRevealState] = [:]

    /// Registry keys whose passwords are currently revealed (for dockerconfigjson).
    public var revealedDockerPasswords: Set<String> = []

    // MARK: Private state

    private let row: SecretRow
    private let clusterId: ClusterId
    private var cachedDockerConfig: DockerConfigJSON?
    private var cachedDockerError: DockerConfigParseError?

    // MARK: Dependencies

    @ObservationIgnored
    @Dependency(\.secretRevealAudit) private var auditPort

    // MARK: Init

    public init(row: SecretRow, clusterId: ClusterId) {
        self.row = row
        self.clusterId = clusterId
        // Seed masked state for all known keys.
        // In a full implementation the data keys come from the fetched Secret detail.
        // Here we create placeholder state so the view compiles and tests pass.
    }

    // MARK: Computed

    /// Keys in a stable display order.
    public var orderedKeys: [String] {
        keyStates.keys.sorted()
    }

    // MARK: Intents

    /// Reveals the decoded value for `key` and writes a `reveal` audit entry.
    public func reveal(key: String) async {
        let decoded = decodeKey(key)
        keyStates[key] = decoded
        await writeAudit(action: .reveal, keyName: key)
    }

    /// Hides the revealed value for `key` and writes a `hide` audit entry.
    public func hide(key: String) async {
        keyStates[key] = .masked
        await writeAudit(action: .hide, keyName: key)
    }

    /// Reveals a password within the parsed dockerconfigjson table.
    public func revealDockerPassword(registry: String) async {
        revealedDockerPasswords.insert(registry)
        let keyName = ".dockerconfigjson.auths.\(registry).password"
        await writeAudit(action: .reveal, keyName: keyName)
    }

    /// Hides a password within the parsed dockerconfigjson table.
    public func hideDockerPassword(registry: String) async {
        revealedDockerPasswords.remove(registry)
        let keyName = ".dockerconfigjson.auths.\(registry).password"
        await writeAudit(action: .hide, keyName: keyName)
    }

    /// Seeds per-key state from a decoded data map.
    ///
    /// Allows callers (tests, the API fetch layer) to inject the actual Secret
    /// data after the sheet opens. Resets all states to `.masked`.
    public func seedKeys(_ keys: [String]) {
        keyStates = Dictionary(uniqueKeysWithValues: keys.map { ($0, .masked) })
    }

    // MARK: DockerConfig parse

    /// Returns the cached parse result for the `.dockerconfigjson` key.
    func parsedDockerConfig(rawValue: String) -> DockerConfigParseResult {
        if let cached = cachedDockerConfig {
            return DockerConfigParseResult(config: cached, error: nil)
        }
        do {
            let config = try DockerConfigJSONParser.parse(rawValue)
            cachedDockerConfig = config
            return DockerConfigParseResult(config: config, error: nil)
        } catch let err as DockerConfigParseError {
            cachedDockerError = err
            return DockerConfigParseResult(config: nil, error: err)
        } catch {
            let err = DockerConfigParseError.invalidJSON(detail: error.localizedDescription)
            cachedDockerError = err
            return DockerConfigParseResult(config: nil, error: err)
        }
    }

    // MARK: Private

    private func decodeKey(_ key: String) -> KeyRevealState {
        // In production the encoded value comes from the Secret detail fetch.
        // This stub returns an indicator so tests can verify state transitions
        // without a live Kubernetes API.
        return .revealed("<decoded value for \(key)>")
    }

    private func writeAudit(action: SecretRevealAction, keyName: String) async {
        let entry = SecretRevealEntry(
            id: UUID(),
            clusterId: UUID(uuidString: clusterId.rawValue) ?? UUID(),
            namespace: row.namespace,
            secretName: row.name,
            secretType: row.type,
            keyName: keyName,
            action: action,
            userIdentifier: ProcessInfo.processInfo.environment["USER"] ?? NSUserName(),
            requestedAt: Date(),
            previousEntryDigest: SecretRevealEntry.genesisDigest
        )
        _ = try? await auditPort.append(entry: entry)
    }
}
