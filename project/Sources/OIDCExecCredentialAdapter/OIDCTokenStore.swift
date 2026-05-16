// OIDCTokenStore.swift — OIDCExecCredentialAdapter
// DDD role: Infrastructure — in-memory OIDC token cache
// ADR-0018 §OIDC: refresh-token cached after first auth; id-token cached while valid.
// Persistence to Keychain is deferred to host app (ADR-0010 KeychainAdapter).

import Foundation

// MARK: - OIDCCachedTokens

/// A snapshot of the tokens returned by the OIDC provider.
public struct OIDCCachedTokens: Sendable {

    /// The raw compact-serialised id-token JWT string.
    public let idToken: String

    /// Optional refresh token. Present after first interactive login; absent for
    /// providers that do not issue refresh tokens on every response.
    public let refreshToken: String?

    /// Expiry derived from the `exp` claim of the id-token. Used to decide
    /// whether a re-fetch is required without another full JWT parse.
    public let expiresAt: Date?

    public init(idToken: String, refreshToken: String?, expiresAt: Date?) {
        self.idToken = idToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Returns `true` when the id-token has not expired (or has no expiry claim),
    /// with a 30-second early-expiry buffer to account for clock skew.
    public func isValid(now: Date = Date()) -> Bool {
        guard let exp = expiresAt else { return true }
        return exp > now.addingTimeInterval(30)
    }
}

// MARK: - OIDCTokenStore

/// Thread-safe in-memory store for OIDC token state keyed by issuer + client-id.
///
/// The store is intentionally scoped to a single process lifetime. Persistence
/// across app launches is the responsibility of the host application's
/// `KeychainAdapter` target (see ADR-0010). The store can be seeded with an
/// initial state loaded from Keychain before the first `resolve` call.
public actor OIDCTokenStore {

    // MARK: State

    private var cache: [CacheKey: OIDCCachedTokens] = [:]

    // MARK: Lifecycle

    public init() {}

    // MARK: Read

    /// Returns cached tokens for the given issuer/client pair, or `nil` when no
    /// entry exists.
    public func tokens(for issuer: String, clientID: String) -> OIDCCachedTokens? {
        cache[CacheKey(issuer: issuer, clientID: clientID)]
    }

    // MARK: Write

    /// Stores or replaces the token entry for the given issuer/client pair.
    public func store(
        idToken: String,
        refreshToken: String?,
        expiresAt: Date?,
        for issuer: String,
        clientID: String
    ) {
        cache[CacheKey(issuer: issuer, clientID: clientID)] = OIDCCachedTokens(
            idToken: idToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt
        )
    }

    /// Removes the entry for the given issuer/client pair. Called when a token
    /// cannot be refreshed and a fresh interactive login is required.
    public func invalidate(for issuer: String, clientID: String) {
        cache.removeValue(forKey: CacheKey(issuer: issuer, clientID: clientID))
    }

    // MARK: Cache key

    private struct CacheKey: Hashable {
        let issuer: String
        let clientID: String
    }
}
