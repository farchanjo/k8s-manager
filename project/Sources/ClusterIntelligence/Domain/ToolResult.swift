// Domain/ToolResult.swift — cluster_intelligence bounded context
// DDD role: ValueObject
// Narrative ref: domain/narrative.md §Ubiquitous language — Invocation, Truncation marker

import Foundation

// MARK: - ToolResult

/// The payload returned to the MCP host after a tool call resolves.
///
/// Wraps the UTF-8 JSON body (truncated if necessary) and the invocation
/// record so callers receive both in one value. Used by `MCPTransportPort`
/// to carry the wire response alongside the auditable log entry.
public struct ToolResult: Sendable {
    /// UTF-8 JSON body to forward to the MCP host.
    public let resultJSON: String
    /// `true` when the body ends with the truncation marker
    /// `{"_truncated":true,"_omittedBytes":<n>}`.
    public let truncated: Bool
    /// The completed invocation record for persistence and diagnostics.
    public let invocation: MCPInvocation

    public init(resultJSON: String, truncated: Bool, invocation: MCPInvocation) {
        self.resultJSON = resultJSON
        self.truncated = truncated
        self.invocation = invocation
    }
}

// MARK: - TruncationMarker

/// Helpers for appending or detecting the standard truncation marker.
///
/// Narrative invariant: oversize payloads are truncated with
/// `{"_truncated":true,"_omittedBytes":<n>}` rather than dropped silently.
public enum TruncationMarker {
    /// Returns a JSON suffix marking truncated output.
    ///
    /// - Parameter omittedBytes: The number of bytes omitted.
    /// - Returns: A UTF-8 JSON string to append to the truncated body.
    public static func suffix(omittedBytes: Int) -> String {
        "{\"_truncated\":true,\"_omittedBytes\":\(omittedBytes)}"
    }

    /// Returns `true` when `json` ends with a truncation marker.
    ///
    /// - Parameter json: The string to inspect.
    public static func isTruncated(_ json: String) -> Bool {
        json.hasSuffix("}")
            && json.contains("\"_truncated\":true")
    }

    /// Truncates `body` to at most `maxBytes`, appending the marker.
    ///
    /// - Parameters:
    ///   - body: The full UTF-8 JSON body.
    ///   - maxBytes: Maximum byte budget for the returned string.
    /// - Returns: The (possibly truncated) body and a `Bool` indicating
    ///   whether truncation occurred.
    public static func apply(to body: String, maxBytes: Int) -> (String, Bool) {
        let fullBytes = body.utf8.count
        guard fullBytes > maxBytes else { return (body, false) }
        // Use worst-case marker length (omittedBytes == fullBytes, largest digit count).
        let worstMarker = suffix(omittedBytes: fullBytes)
        let worstMarkerBytes = worstMarker.utf8.count
        let budget = maxBytes - worstMarkerBytes
        guard budget > 0 else { return (suffix(omittedBytes: fullBytes), true) }
        // Slice body to budget bytes, respecting UTF-8 character boundaries.
        var prefixBytes = Array(body.utf8.prefix(budget))
        // Drop trailing partial UTF-8 sequence if any.
        while !prefixBytes.isEmpty, String(bytes: prefixBytes, encoding: .utf8) == nil {
            prefixBytes.removeLast()
        }
        let truncatedPrefix = String(bytes: prefixBytes, encoding: .utf8) ?? ""
        let omitted = fullBytes - prefixBytes.count
        return (truncatedPrefix + suffix(omittedBytes: omitted), true)
    }
}
