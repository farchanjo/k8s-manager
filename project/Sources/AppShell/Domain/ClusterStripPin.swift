// Domain/ClusterStripPin.swift — app_shell bounded context
// DDD role: ValueObject
// ADR ref: ADR-0051 (multi-cluster workspace, cluster strip pinning)
// CUE source: docs/arch/contexts/app_shell/schemas/cluster_strip_pin.cue

import Foundation
import CryptoKit
import SharedKernel

// MARK: - ClusterAvatarColor

/// Deterministic 8-color palette for cluster avatar backgrounds.
///
/// Color is assigned by computing `SHA-256(clusterId.rawValue) mod 8` so it is
/// stable across restarts and matches the Rego invariant in `tab_navigation_policy.rego`.
public enum ClusterAvatarColor: String, CaseIterable, Sendable, Codable {
    case purple = "#7E57C2"
    case blue = "#42A5F5"
    case teal = "#26A69A"
    case green = "#66BB6A"
    case amber = "#FFA726"
    case red = "#EF5350"
    case pink = "#EC407A"
    case indigo = "#5C6BC0"

    /// Returns the palette entry deterministically assigned to `clusterId`.
    ///
    /// Algorithm: SHA-256 over the UTF-8 bytes of `clusterId.rawValue`; the first
    /// byte of the digest modulo ``allCases.count`` selects the index.
    public static func deterministic(for clusterId: ClusterId) -> ClusterAvatarColor {
        let digest = SHA256.hash(data: Data(clusterId.rawValue.utf8))
        let bytes = Array(digest)
        let index = Int(bytes[0]) % allCases.count
        return allCases[index]
    }
}

// MARK: - ClusterStripPin

/// Value object representing one pinned cluster entry in the vertical cluster strip.
///
/// Conforms to `Identifiable` keyed by ``clusterId`` so SwiftUI `ForEach` can
/// use it directly. `Codable` for JSON persistence by ``ClusterStripActor``.
/// All fields are immutable after construction; mutations produce a new value.
public struct ClusterStripPin: Sendable, Codable, Hashable, Identifiable {

    // MARK: Stored properties

    /// Stable cluster identifier; also the `Identifiable.id`.
    public let clusterId: ClusterId

    /// Human-readable cluster name shown in the avatar tooltip.
    public let displayName: String

    /// 1–3 uppercase characters rendered inside the avatar circle.
    ///
    /// Derived from `displayName` at pin time: first letter of each word
    /// (up to 3 words); falls back to the first 2 characters for single-word names.
    public let initials: String

    /// Hex string of the deterministic avatar background color (e.g. `"#7E57C2"`).
    public let colorHex: String

    /// RFC 3339 timestamp recording when this cluster was pinned.
    public let pinnedAtRFC3339: String

    /// Zero-based strip position (top = 0). Contiguous across the full pin list.
    public let order: Int

    // MARK: Identifiable

    /// `Identifiable.id` delegates to `clusterId` for SwiftUI list diffing.
    public var id: ClusterId { clusterId }

    // MARK: Init

    /// Designated initialiser.
    public init(
        clusterId: ClusterId,
        displayName: String,
        initials: String,
        colorHex: String,
        pinnedAtRFC3339: String,
        order: Int
    ) {
        self.clusterId = clusterId
        self.displayName = displayName
        self.initials = initials
        self.colorHex = colorHex
        self.pinnedAtRFC3339 = pinnedAtRFC3339
        self.order = order
    }

    /// Convenience factory that derives `initials` and `colorHex` automatically.
    public static func make(
        clusterId: ClusterId,
        displayName: String,
        pinnedAtRFC3339: String,
        order: Int
    ) -> ClusterStripPin {
        ClusterStripPin(
            clusterId: clusterId,
            displayName: displayName,
            initials: Self.deriveInitials(from: displayName),
            colorHex: ClusterAvatarColor.deterministic(for: clusterId).rawValue,
            pinnedAtRFC3339: pinnedAtRFC3339,
            order: order
        )
    }

    // MARK: Helpers

    /// Derives 1–3 uppercase initials from `displayName`.
    ///
    /// Strategy: split on whitespace and hyphens, take the first character of each
    /// word (up to 3 words). For a single-word name with no separators, take the
    /// first 2 characters. Always uppercased.
    static func deriveInitials(from displayName: String) -> String {
        let separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-_"))
        let words = displayName
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        guard words.count > 1 else {
            let prefix = displayName.prefix(2)
            return prefix.uppercased()
        }
        let letters = words.prefix(3).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }
}
