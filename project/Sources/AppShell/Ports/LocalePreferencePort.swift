// Ports/LocalePreferencePort.swift — app_shell bounded context
// DDD role: Port (re-export from local_persistence)
// ADR ref: ADR-0033

// MARK: - LocalePreferencePort

/// Port for reading and writing the operator's `LocalePreference`.
///
/// The actual persistence implementation lives in the `local_persistence` bounded context.
/// This port is declared in `app_shell` so the `LocaleResolverService` domain service
/// can depend on the abstraction without importing infrastructure.
public protocol LocalePreferencePort: Sendable {
    /// Loads the persisted locale preference, or returns `LocalePreference.defaults` if absent.
    func load() async throws -> LocalePreference

    /// Persists the updated locale preference.
    func save(_ preference: LocalePreference) async throws
}

// MARK: - InMemoryLocalePreferenceStore (test double)

/// In-memory test double for `LocalePreferencePort`.
public actor InMemoryLocalePreferenceStore: LocalePreferencePort {
    private var stored: LocalePreference

    public init(initial: LocalePreference = .defaults) {
        self.stored = initial
    }

    public func load() async throws -> LocalePreference { stored }

    public func save(_ preference: LocalePreference) async throws {
        stored = preference
    }
}
