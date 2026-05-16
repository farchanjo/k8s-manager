// Domain/DockerConfigJSON.swift — app_shell bounded context
// DDD role: Value Object (parsed shape for kubernetes.io/dockerconfigjson)
// ADR refs: ADR-0063 (secret reveal/hide + dockerconfigjson parser §Special type parsers)

import Foundation

// MARK: - DockerConfigRegistry

/// Parsed credentials for one registry entry in a `dockerconfigjson` auths map.
public struct DockerConfigRegistry: Hashable, Sendable {
    /// Registry hostname as it appears in the `auths` map key.
    public let registry: String
    /// Decoded username, or `nil` when absent.
    public let username: String?
    /// Decoded password, or `nil` when absent.
    public let password: String?

    public init(registry: String, username: String?, password: String?) {
        self.registry = registry
        self.username = username
        self.password = password
    }
}

// MARK: - DockerConfigJSON

/// Parsed representation of a `kubernetes.io/dockerconfigjson` secret value.
///
/// Supports both the standard format (`auths.<registry>.username` /
/// `auths.<registry>.password`) and the legacy format where credentials
/// are encoded as `"user:pass"` in the `auth` base64 field.
public struct DockerConfigJSON: Hashable, Sendable {
    /// One entry per registry key found in the `auths` map.
    public let registries: [DockerConfigRegistry]

    public init(registries: [DockerConfigRegistry]) {
        self.registries = registries
    }
}

// MARK: - DockerConfigParseError

/// Errors that `DockerConfigJSONParser` can return.
public enum DockerConfigParseError: Error, Sendable, Equatable {
    /// The base64-decoded bytes are not valid JSON.
    case invalidJSON(detail: String)
    /// The JSON is valid but contains no `auths` (or `Auth`) map.
    case missingAuthsMap
}

// MARK: - DockerConfigJSONParser

/// Parses the raw value of the `.dockerconfigjson` key in a
/// `kubernetes.io/dockerconfigjson` secret.
///
/// Per ADR-0063 §Parsing rules:
///
/// 1. Decode the base64 value.
/// 2. Parse as JSON; fall back on error.
/// 3. Navigate to `.auths` or `.Auth` (legacy).
/// 4. For each registry, extract `.username` / `.password` or decode
///    `.auth` as `user:pass` base64.
/// 5. Empty username or password fields produce `nil`.
public enum DockerConfigJSONParser {

    // MARK: Public API

    /// Parses `rawBase64` — the base64-encoded `.dockerconfigjson` value from
    /// the Kubernetes API.
    ///
    /// - Parameter rawBase64: Base64-encoded JSON bytes.
    /// - Returns: A parsed `DockerConfigJSON` value.
    /// - Throws: `DockerConfigParseError` on malformed input.
    public static func parse(_ rawBase64: String) throws -> DockerConfigJSON {
        let jsonData = try decodeBase64(rawBase64)
        return try parseJSONData(jsonData)
    }

    /// Parses already-decoded JSON data (skips the base64 step).
    ///
    /// Useful when the caller has already decoded the base64 value for display
    /// and wants the structured representation in the same pass.
    public static func parseJSONData(_ jsonData: Data) throws -> DockerConfigJSON {
        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            let preview = String(data: jsonData.prefix(120), encoding: .utf8) ?? "<binary>"
            throw DockerConfigParseError.invalidJSON(detail: preview)
        }
        let auths = authsMap(from: root)
        guard let auths else {
            throw DockerConfigParseError.missingAuthsMap
        }
        let registries = auths.compactMap { registryEntry(key: $0.key, value: $0.value) }
        return DockerConfigJSON(registries: registries.sorted { $0.registry < $1.registry })
    }

    // MARK: Private helpers

    private static func decodeBase64(_ raw: String) throws -> Data {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Kubernetes uses standard base64 with optional padding.
        var padded = trimmed
        let remainder = padded.count % 4
        if remainder != 0 {
            padded += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: padded) else {
            throw DockerConfigParseError.invalidJSON(detail: "base64 decode failed")
        }
        return data
    }

    private static func authsMap(from root: [String: Any]) -> [String: Any]? {
        if let auths = root["auths"] as? [String: Any] { return auths }
        if let auth = root["Auth"] as? [String: Any] { return auth }
        return nil
    }

    private static func registryEntry(key: String, value: Any) -> DockerConfigRegistry? {
        guard let creds = value as? [String: Any] else { return nil }

        if let username = creds["username"] as? String,
           let password = creds["password"] as? String {
            return DockerConfigRegistry(
                registry: key,
                username: emptyToNil(username),
                password: emptyToNil(password)
            )
        }

        // Legacy: `auth` = base64("user:pass")
        if let authField = creds["auth"] as? String,
           let decoded = decodeAuthField(authField) {
            return DockerConfigRegistry(
                registry: key,
                username: emptyToNil(decoded.user),
                password: emptyToNil(decoded.pass)
            )
        }

        return DockerConfigRegistry(registry: key, username: nil, password: nil)
    }

    private static func decodeAuthField(_ raw: String) -> (user: String, pass: String)? {
        var padded = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = padded.count % 4
        if remainder != 0 { padded += String(repeating: "=", count: 4 - remainder) }
        guard let data = Data(base64Encoded: padded),
              let string = String(data: data, encoding: .utf8) else { return nil }
        let parts = string.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (user: parts[0], pass: parts[1])
    }

    private static func emptyToNil(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }
}
