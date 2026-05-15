// SharedKernel.swift — domain core placeholder
// Bounded context: shared_kernel (per ADR-0005)
// Status: skeleton; domain types pending CUE schema extraction.
import Foundation

/// Namespace marker for the SharedKernel bounded context.
///
/// Domain types, ports, and actors land under this enum in subsequent rounds.
/// This file exists so the target compiles cleanly under Swift 6 strict concurrency.
public enum SharedKernel: Sendable {
    /// Build identifier — bumped manually until CI emits this.
    public static let moduleVersion = "0.0.1-skeleton"
}

// MARK: - ADR-0020 §174-177 core value types

/// Stable identifier for a kubeconfig cluster entry.
public struct ClusterId: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Stable identifier for a kubeconfig context entry.
public struct ContextId: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Path on disk where kubeconfig YAML lives.
public struct KubeconfigPath: Hashable, Sendable, Codable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
}

/// Monotonic clock contract; tests substitute a frozen clock.
public protocol RFC3339Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: RFC3339Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// UUIDv7 generator (time-ordered) backed by Foundation UUID + millisecond timestamp.
public enum UUIDv7 {
    public static func generate(now: Date = Date()) -> UUID {
        let ms = UInt64(now.timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8((ms >> 40) & 0xff)
        bytes[1] = UInt8((ms >> 32) & 0xff)
        bytes[2] = UInt8((ms >> 24) & 0xff)
        bytes[3] = UInt8((ms >> 16) & 0xff)
        bytes[4] = UInt8((ms >> 8) & 0xff)
        bytes[5] = UInt8(ms & 0xff)
        let random = (0..<10).map { _ in UInt8.random(in: 0...255) }
        for i in 0..<10 { bytes[6 + i] = random[i] }
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                           bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11],
                           bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
