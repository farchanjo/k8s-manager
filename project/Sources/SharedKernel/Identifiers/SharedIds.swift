// SharedIds.swift — new typed identifier wrappers per shared_kernel.cue
// Bounded context: shared_kernel
// Spec:           docs/arch/contexts/_shared/schemas/shared_kernel.cue
//                 (#ProviderProfileId, #EditorSessionId)
//
// Existing types (ClusterId, ContextId, KubeconfigPath, UUIDv7, SystemClock)
// are defined in Sources/SharedKernel/SharedKernel.swift and are left untouched.
//
// Both wrappers use RawRepresentable<String> so callers can initialise with a
// plain String literal without importing Foundation just for UUID.

// MARK: - ProviderProfileId

/// Uniquely identifies an LLM provider profile stored in local persistence.
///
/// Backed by a UUIDv7 string (RFC 9562 §5.7) per `#ProviderProfileId` in
/// `shared_kernel.cue`. Use ``UUIDv7/generate()`` to produce a new value.
public struct ProviderProfileId: Sendable, Hashable, Codable, RawRepresentable {
    public let rawValue: String

    /// Designated initialiser.
    ///
    /// - Parameter rawValue: A UUIDv7 string in canonical lowercase hyphenated form.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Convenience initialiser accepting a plain `String` literal.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

// MARK: - EditorSessionId

/// Uniquely identifies an open editor session in the `resource_browser` context.
///
/// Backed by a UUIDv7 string (RFC 9562 §5.7) per `#EditorSessionId` in
/// `shared_kernel.cue`. Carried in ``DraftSaved/payload`` to correlate a draft
/// with its originating session.
public struct EditorSessionId: Sendable, Hashable, Codable, RawRepresentable {
    public let rawValue: String

    /// Designated initialiser.
    ///
    /// - Parameter rawValue: A UUIDv7 string in canonical lowercase hyphenated form.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Convenience initialiser accepting a plain `String` literal.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}
