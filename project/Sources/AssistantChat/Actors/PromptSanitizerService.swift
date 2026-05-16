// Actors/PromptSanitizerService.swift — assistant_chat bounded context
// DDD role: DomainService (Layer 1 of ADR-0048 prompt injection defence)
// ADR ref: ADR-0048 (LLM prompt injection defence — Layer 1: input sanitization)

import Foundation
import SharedKernel

// MARK: - SanitizationResult

/// Outcome of running a cluster-origin string through Layer 1 sanitization.
public struct SanitizationResult: Sendable, Equatable {
    /// The sanitized string ready for Layer 2 tagging and Layer 3 filtering.
    public let sanitized: String

    /// `true` when the original value was clipped to `maxLength`.
    public let wasTruncated: Bool

    /// Length of the original input in Unicode scalars, populated only when
    /// `wasTruncated` is `true`. Used for the truncation marker.
    public let originalLength: Int

    public init(sanitized: String, wasTruncated: Bool, originalLength: Int) {
        self.sanitized = sanitized
        self.wasTruncated = wasTruncated
        self.originalLength = originalLength
    }
}

// MARK: - PromptSanitizerService

/// Layer 1 of the ADR-0048 defence-in-depth model.
///
/// Applies three deterministic transforms to every cluster-origin string:
/// 1. Strip ASCII control characters 0x00–0x1F and 0x7F, except `\n` (0x0A)
///    and `\t` (0x09), which are safe whitespace and preserved.
/// 2. Normalize Unicode to NFC (Canonical Decomposition + Canonical Composition)
///    to prevent homoglyph and combining-character obfuscation.
/// 3. Clip each field value to `maxLength` characters (default 4096); append a
///    truncation marker when clipping occurs.
///
/// This is a pure, stateless value type — no actor isolation required.
public struct PromptSanitizerService: Sendable {
    // MARK: Configuration

    /// Maximum Unicode scalar count before truncation. Configurable for testing.
    public let maxLength: Int

    // MARK: - Init

    /// Creates a sanitizer with an explicit length cap.
    ///
    /// - Parameter maxLength: Maximum allowed character count. Defaults to 4096.
    public init(maxLength: Int = 4096) {
        self.maxLength = maxLength
    }

    // MARK: - Public API

    /// Sanitizes `input` by stripping control characters, applying NFC
    /// normalization, and clipping to `maxLength`.
    ///
    /// - Parameter input: Raw cluster-origin string.
    /// - Returns: A `SanitizationResult` with the processed string and
    ///   truncation metadata.
    public func sanitize(_ input: String) -> SanitizationResult {
        let stripped = stripControlCharacters(input)
        let normalized = stripped.precomposedStringWithCanonicalMapping
        return clip(normalized, originalRaw: input)
    }

    // MARK: - Private helpers

    private func stripControlCharacters(_ value: String) -> String {
        value.unicodeScalars
            .filter { scalar in
                let v = scalar.value
                // Preserve \t (0x09) and \n (0x0A); strip 0x00-0x1F and 0x7F.
                if v == 0x09 || v == 0x0A { return true }
                if v <= 0x1F || v == 0x7F { return false }
                return true
            }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    private func clip(_ value: String, originalRaw: String) -> SanitizationResult {
        guard value.count > maxLength else {
            return SanitizationResult(sanitized: value, wasTruncated: false, originalLength: 0)
        }
        let clipped = String(value.prefix(maxLength))
        let marker = " [truncated — original length: \(originalRaw.count) chars]"
        return SanitizationResult(
            sanitized: clipped + marker,
            wasTruncated: true,
            originalLength: originalRaw.count
        )
    }
}
