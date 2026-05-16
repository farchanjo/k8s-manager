// DateFormatting.swift — GRDBPersistenceAdapter
// Shared ISO 8601 date serialisation helpers.
// ISO8601DateFormatter is not Sendable; we create a new instance per call
// to satisfy Swift 6 strict-concurrency checking in Sendable struct adapters.

import Foundation

// MARK: - Module-level helpers

/// Formats `date` as an RFC 3339 string with fractional seconds.
func iso8601String(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.string(from: date)
}

/// Parses an RFC 3339 string, falling back to epoch on failure.
func parseISO8601(_ string: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: string) ?? Date(timeIntervalSince1970: 0)
}
