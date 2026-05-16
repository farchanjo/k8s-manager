// SharedKernel/FailureMode/ErrorMapper.swift — shared_kernel bounded context
// DDD role: Anti-corruption-layer utility
// ADR ref: ADR-0041 (failure-mode catalogue), ADR-0005 (bounded context isolation)

import Foundation

// MARK: - ErrorMapper

/// Translates common Swift error types to ``FailureCatalogue`` entries.
///
/// Call sites in view models (or any bounded context adapter) pass a caught
/// `Error` to ``ErrorMapper.entry(for:)`` and receive a ``FailureMode`` that
/// encodes a user-visible message, severity, and recovery strategy — removing
/// ad-hoc switch statements across the codebase.
///
/// Mapping priority (first match wins):
/// 1. Catalogue lookup by error-domain pattern (URLError, CocoaError, DecodingError).
/// 2. HTTP status code pattern via ``HTTPStatusError``.
/// 3. POSIX error code (ENOSPC → F18, ENOLCK → F20).
/// 4. Generic fallback (F01 — network unreachable).
public enum ErrorMapper {

    // MARK: Public API

    /// Returns the ``FailureMode`` that best describes `error`, or a generic
    /// fallback entry when no specific mapping is found.
    ///
    /// - Parameter error: Any `Error` caught in a critical code path.
    /// - Returns: A non-nil ``FailureMode`` drawn from ``FailureCatalogue``.
    public static func entry(for error: any Error) -> FailureMode {
        if let mapped = mapURLError(error) { return mapped }
        if let mapped = mapCocoaError(error) { return mapped }
        if let mapped = mapDecodingError(error) { return mapped }
        if let mapped = mapHTTPStatus(error) { return mapped }
        if let mapped = mapPOSIX(error) { return mapped }
        return fallbackEntry
    }

    // MARK: Private mapping helpers

    private static func mapURLError(_ error: any Error) -> FailureMode? {
        guard let urlError = error as? URLError else { return nil }
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost,
             .networkConnectionLost, .timedOut, .cannotFindHost:
            return FailureCatalogue.entry(for: "F01")
        case .userAuthenticationRequired:
            return FailureCatalogue.entry(for: "F02")
        default:
            return FailureCatalogue.entry(for: "F01")
        }
    }

    private static func mapCocoaError(_ error: any Error) -> FailureMode? {
        guard let cocoa = error as? CocoaError else { return nil }
        // ENOSPC surfaces as NSFileWriteOutOfSpaceError in CocoaError.
        if cocoa.code == .fileWriteOutOfSpace {
            return FailureCatalogue.entry(for: "F18")
        }
        // File not found / no-such-file is transient — treat as reload.
        if cocoa.code == .fileReadNoSuchFile || cocoa.code == .fileNoSuchFile {
            return FailureCatalogue.entry(for: "F03")
        }
        return nil
    }

    private static func mapDecodingError(_ error: any Error) -> FailureMode? {
        guard error is DecodingError else { return nil }
        // A DecodingError on a Helm secret payload → F16.
        return FailureCatalogue.entry(for: "F16")
    }

    private static func mapHTTPStatus(_ error: any Error) -> FailureMode? {
        guard let http = error as? HTTPStatusError else { return nil }
        switch http.statusCode {
        case 401: return FailureCatalogue.entry(for: "F02")
        case 409: return FailureCatalogue.entry(for: "F04")
        case 410: return FailureCatalogue.entry(for: "F03")
        case 429: return FailureCatalogue.entry(for: "F07")
        case 503: return FailureCatalogue.entry(for: "F01")
        default: return nil
        }
    }

    private static func mapPOSIX(_ error: any Error) -> FailureMode? {
        let nsError = error as NSError
        guard nsError.domain == NSPOSIXErrorDomain else { return nil }
        switch Int32(nsError.code) {
        case ENOSPC: return FailureCatalogue.entry(for: "F18")
        case ENOLCK: return FailureCatalogue.entry(for: "F20")
        default: return nil
        }
    }

    /// Generic fallback when no specific mapping matches.
    private static var fallbackEntry: FailureMode {
        FailureCatalogue.entry(for: "F01")
            ?? FailureMode(
                code: "F00",
                title: "Unknown Error",
                userMessage: "An unexpected error occurred. Please try again.",
                recovery: .retry,
                severity: .error
            )
    }
}

// MARK: - HTTPStatusError

/// Lightweight carrier for HTTP status-code errors so ``ErrorMapper`` can
/// pattern-match without importing URLSession/AsyncHTTPClient directly.
///
/// Domain adapters wrap their HTTP responses in this error type before
/// re-throwing across the anti-corruption boundary.
public struct HTTPStatusError: Error, Sendable {
    /// The HTTP response status code (e.g. 401, 409, 429).
    public let statusCode: Int
    /// Human-readable message from the server, if available.
    public let serverMessage: String?

    public init(statusCode: Int, serverMessage: String? = nil) {
        self.statusCode = statusCode
        self.serverMessage = serverMessage
    }
}
