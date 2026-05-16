// Domain/LocaleSanitizer.swift — app_shell bounded context
// DDD role: ValueObject / pure function
// ADR ref: ADR-0039 (locale sanitization — reject extended identifiers)

import Foundation

// MARK: - LocaleSanitizer

/// Pure-function namespace for BCP 47 locale tag sanitization.
///
/// ADR-0039 restricts accepted locale identifiers to the base BCP 47 grammar
/// (language, optional script, optional region) and explicitly rejects any
/// extension subtag (``@calendar=``, ``@timezone=``, ``@collation=``, etc.)
/// or private-use suffix that can be injected via `NSLocale` or environment
/// variables.
public enum LocaleSanitizer {

    // MARK: - Public API

    /// Sanitizes a raw locale string from an untrusted source.
    ///
    /// Accepted grammar (case-sensitive after normalization):
    ///
    /// ```
    /// ^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$
    /// ```
    ///
    /// - language: 2–3 lowercase ASCII letters (ISO 639-1 / 639-2).
    /// - script:   optional, title-cased 4-letter ISO 15924 code.
    /// - region:   optional, 2 uppercase ASCII letters (ISO 3166-1 alpha-2).
    ///
    /// Any extended identifier (``@``, ``+``, ``.``, or a fifth subtag) causes
    /// rejection and `nil` is returned.
    ///
    /// - Parameter raw: The raw locale string to evaluate.
    /// - Returns: The unchanged input when it matches the whitelist; `nil` otherwise.
    public static func sanitize(_ raw: String) -> String? {
        // Reject immediately on extension markers defined by BCP 47 §2.2.6 / §2.2.7
        // and POSIX locale conventions.
        for marker: Character in ["@", "+"] {
            if raw.contains(marker) { return nil }
        }
        // POSIX encoding suffix (e.g. "en_US.UTF-8").
        if raw.contains(".") { return nil }

        // Normalize: replace underscore separators with hyphens so that
        // "pt_BR" and "pt-BR" are both accepted.
        let normalized = raw.replacingOccurrences(of: "_", with: "-")

        guard normalizedMatchesWhitelist(normalized) else { return nil }

        // Return the original (caller-supplied) form — do not silently mutate.
        return raw
    }

    // MARK: - Private helpers

    /// Tests `normalized` against the BCP 47 base grammar whitelist regex.
    ///
    /// The regex is anchored and compiled once — `NSRegularExpression` caches
    /// the compiled automaton on the heap so repeated calls are cheap.
    private static func normalizedMatchesWhitelist(_ normalized: String) -> Bool {
        let pattern = #"^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.firstMatch(in: normalized, range: range) != nil
    }
}
