// OIDCExecCredentialAdapter.swift — OIDCExecCredentialAdapter target
// DDD role: Adapter (outbound port implementation)
// Implements: ExecPluginPort from ClusterConnectivity
// Tier B import: AppAuth-iOS (not yet Swift 6 language mode — wrapped here)
// ADR-0018 §OIDC generic authentication protocol
// ADR-0019 §Tier B: @preconcurrency import boundary; annotation must not propagate to domain core.

@preconcurrency import AppAuth
#if os(macOS)
import AppKit
#endif
import ClusterConnectivity
import Foundation
import JWTKit
import Logging

// MARK: - OIDCAuthProviderConfig

/// The subset of kubeconfig `auth-provider` fields consumed by this adapter.
///
/// Fields are read from `ExecPluginAuth.env` and from a conventional `args`
/// mapping that kubelogin-style plugins encode in the kubeconfig. The adapter
/// falls back gracefully when optional fields are absent.
public struct OIDCAuthProviderConfig: Sendable {

    /// The OIDC issuer URL (e.g. `https://accounts.google.com`).
    public let idpIssuerURL: String

    /// The OIDC `client_id` registered for this application.
    public let clientID: String

    /// Optional `client_secret` (confidential clients only).
    public let clientSecret: String?

    /// Refresh token from a previous successful login session.
    public var refreshToken: String?

    /// Cached id-token from a previous successful login session.
    public var idToken: String?

    /// Extra OAuth scopes appended to the default `openid` scope.
    public let extraScopes: [String]

    public init(
        idpIssuerURL: String,
        clientID: String,
        clientSecret: String? = nil,
        refreshToken: String? = nil,
        idToken: String? = nil,
        extraScopes: [String] = []
    ) {
        self.idpIssuerURL = idpIssuerURL
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.extraScopes = extraScopes
    }
}

// MARK: - OIDCAdapterError

/// Errors specific to the OIDC adapter layer.
public enum OIDCAdapterError: Error, Sendable {

    /// The kubeconfig `auth` value does not contain the required OIDC fields.
    case missingConfig(field: String)

    /// The id-token JWT failed signature verification against the JWKS.
    case tokenVerificationFailed(detail: String)

    /// The refresh-token grant was rejected by the provider.
    case refreshFailed(detail: String)

    /// The interactive auth-code flow failed or was cancelled.
    case interactiveFailed(detail: String)

    /// A network error occurred during discovery or token fetch.
    case networkError(detail: String)

    /// The issuer URL is malformed.
    case invalidIssuerURL(raw: String)

    /// An interactive session was required but `interactiveMode == .never`.
    case interactiveModeProhibited
}

// MARK: - OIDCIDTokenPayload

/// Minimal JWTKit payload used only to extract the `exp` claim for cache TTL.
struct OIDCIDTokenPayload: JWTPayload, Sendable {

    var exp: ExpirationClaim?
    var iss: IssuerClaim?

    func verify(using algorithm: some JWTAlgorithm) async throws {
        // Signature verification is already done by JWTKeyCollection.verify(_:).
        // The only additional check needed here is expiry.
        try exp?.verifyNotExpired()
    }

    private enum CodingKeys: String, CodingKey {
        case exp, iss
    }
}

// MARK: - OIDCExecCredentialAdapter

/// Resolves OIDC bearer tokens for kubeconfig exec-credential entries that
/// target a generic OIDC provider (e.g. Dex, Keycloak, Okta).
///
/// Resolution priority:
/// 1. Cached id-token (signature-valid + not expired) — returned immediately.
/// 2. Refresh-token grant — POST to `<issuer>/token`, caches new tokens.
/// 3. AppAuth authorization-code flow with PKCE — opens browser, caches result.
///
/// The actor isolates all mutable state (token cache, in-flight request tracking)
/// from the surrounding concurrency domain. The `@preconcurrency` import of
/// AppAuth is confined to this file and must not be re-exported.
public actor OIDCExecCredentialAdapter: ExecPluginPort {

    // MARK: Dependencies

    private let discoveryClient: OIDCDiscoveryClient
    private let tokenStore: OIDCTokenStore
    private let session: URLSession
    private let logger: Logger

    // MARK: Lifecycle

    /// Creates an adapter instance suitable for production use.
    ///
    /// - Parameters:
    ///   - session: URLSession injected for network calls and CA-bundle pinning.
    ///   - logger: Structured logger.
    public init(
        session: URLSession = .shared,
        logger: Logger = Logger(label: "OIDCExecCredentialAdapter")
    ) {
        self.session = session
        self.discoveryClient = OIDCDiscoveryClient(session: session, logger: logger)
        self.tokenStore = OIDCTokenStore()
        self.logger = logger
    }

    // MARK: ExecPluginPort

    /// Resolves an OIDC bearer token for the given exec-plugin auth configuration.
    ///
    /// Reads OIDC parameters from `ExecPluginAuth.env` (same convention used by
    /// `kubelogin` and `oidc-login`):
    /// - `OIDC_ISSUER_URL` / `IDP_ISSUER_URL`
    /// - `OIDC_CLIENT_ID` / `CLIENT_ID`
    /// - `OIDC_CLIENT_SECRET` / `CLIENT_SECRET`
    /// - `OIDC_ID_TOKEN` / `ID_TOKEN`
    /// - `OIDC_REFRESH_TOKEN` / `REFRESH_TOKEN`
    /// - `OIDC_EXTRA_SCOPES` / `EXTRA_SCOPES` (comma-separated)
    ///
    /// - Parameter auth: Exec-plugin parameters from the kubeconfig user entry.
    /// - Returns: `AuthInfo.bearerToken` wrapping the resolved id-token.
    /// - Throws: `OIDCAdapterError` or `ExecPluginError`.
    public func resolve(auth: ExecPluginAuth) async throws -> AuthInfo {
        let config = try extractConfig(from: auth)
        let idToken = try await resolveIDToken(config: config)
        return .bearerToken(BearerTokenAuth(token: idToken))
    }

    // MARK: Private — config extraction

    private func extractConfig(from auth: ExecPluginAuth) throws -> OIDCAuthProviderConfig {
        let envMap = Dictionary(uniqueKeysWithValues: auth.env.map { ($0.name, $0.value) })

        guard let issuer = envMap["OIDC_ISSUER_URL"] ?? envMap["IDP_ISSUER_URL"] else {
            throw OIDCAdapterError.missingConfig(field: "OIDC_ISSUER_URL")
        }
        guard let clientID = envMap["OIDC_CLIENT_ID"] ?? envMap["CLIENT_ID"] else {
            throw OIDCAdapterError.missingConfig(field: "OIDC_CLIENT_ID")
        }

        let rawScopes = envMap["OIDC_EXTRA_SCOPES"] ?? envMap["EXTRA_SCOPES"] ?? ""
        let extraScopes = rawScopes.isEmpty ? [] : rawScopes.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        return OIDCAuthProviderConfig(
            idpIssuerURL: issuer,
            clientID: clientID,
            clientSecret: envMap["OIDC_CLIENT_SECRET"] ?? envMap["CLIENT_SECRET"],
            refreshToken: envMap["OIDC_REFRESH_TOKEN"] ?? envMap["REFRESH_TOKEN"],
            idToken: envMap["OIDC_ID_TOKEN"] ?? envMap["ID_TOKEN"],
            extraScopes: extraScopes
        )
    }

    // MARK: Private — resolution cascade

    private func resolveIDToken(config: OIDCAuthProviderConfig) async throws -> String {
        guard let issuerURL = URL(string: config.idpIssuerURL) else {
            throw OIDCAdapterError.invalidIssuerURL(raw: config.idpIssuerURL)
        }

        // Step 1: validate cached id-token if present
        if let cached = await tokenStore.tokens(for: config.idpIssuerURL, clientID: config.clientID),
           cached.isValid() {
            logger.debug("OIDC: returning cached valid id-token")
            return cached.idToken
        }

        // Also check config-supplied id-token (from kubeconfig, pre-seeded)
        if let rawIDToken = config.idToken, !rawIDToken.isEmpty {
            if await isValidIDToken(rawIDToken, issuerURL: issuerURL) {
                logger.debug("OIDC: kubeconfig id-token is still valid")
                let exp = try? expiry(from: rawIDToken)
                await tokenStore.store(
                    idToken: rawIDToken,
                    refreshToken: config.refreshToken,
                    expiresAt: exp,
                    for: config.idpIssuerURL,
                    clientID: config.clientID
                )
                return rawIDToken
            }
        }

        let discovery = try await discoveryClient.fetchDiscovery(issuerURL: issuerURL)

        // Step 2: refresh-token grant
        let cachedRefreshToken = await tokenStore.tokens(
            for: config.idpIssuerURL, clientID: config.clientID
        )?.refreshToken
        if let refreshToken = config.refreshToken ?? cachedRefreshToken {
            logger.debug("OIDC: attempting refresh-token grant")
            do {
                return try await performRefreshGrant(
                    refreshToken: refreshToken,
                    config: config,
                    discovery: discovery,
                    issuerURL: issuerURL
                )
            } catch {
                logger.warning(
                    "OIDC: refresh-token grant failed, falling back to interactive flow",
                    metadata: ["error": "\(error)"]
                )
                await tokenStore.invalidate(for: config.idpIssuerURL, clientID: config.clientID)
            }
        }

        // Step 3: interactive AppAuth PKCE flow
        logger.info("OIDC: starting interactive authorization-code flow")
        return try await performInteractiveFlow(
            config: config,
            discovery: discovery,
            issuerURL: issuerURL
        )
    }

    // MARK: Private — refresh-token grant

    private func performRefreshGrant(
        refreshToken: String,
        config: OIDCAuthProviderConfig,
        discovery: OIDCDiscoveryDocument,
        issuerURL: URL
    ) async throws -> String {
        guard let tokenEndpointURL = URL(string: discovery.tokenEndpoint) else {
            throw OIDCAdapterError.networkError(detail: "Invalid token endpoint URL")
        }

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ]
        if let secret = config.clientSecret {
            body.queryItems?.append(URLQueryItem(name: "client_secret", value: secret))
        }

        var request = URLRequest(url: tokenEndpointURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.query?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw OIDCAdapterError.refreshFailed(
                detail: "HTTP \(statusCode): \(String(data: data, encoding: .utf8) ?? "(empty)")"
            )
        }

        let tokenResponse = try parseTokenResponse(data)
        guard let idToken = tokenResponse.idToken else {
            throw OIDCAdapterError.refreshFailed(detail: "No id_token in refresh response")
        }

        let exp = try? expiry(from: idToken)
        await tokenStore.store(
            idToken: idToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            expiresAt: exp,
            for: config.idpIssuerURL,
            clientID: config.clientID
        )
        logger.debug("OIDC: refresh-token grant succeeded")
        return idToken
    }

    // MARK: Private — AppAuth interactive flow

    private func performInteractiveFlow(
        config: OIDCAuthProviderConfig,
        discovery: OIDCDiscoveryDocument,
        issuerURL: URL
    ) async throws -> String {
        guard
            let authEndpointURL = URL(string: discovery.authorizationEndpoint),
            let tokenEndpointURL = URL(string: discovery.tokenEndpoint)
        else {
            throw OIDCAdapterError.interactiveFailed(detail: "Malformed endpoint URLs in discovery")
        }

        let serviceConfig = OIDServiceConfiguration(
            authorizationEndpoint: authEndpointURL,
            tokenEndpoint: tokenEndpointURL,
            issuer: issuerURL
        )

        var scopes: [String] = [OIDScopeOpenID, OIDScopeProfile]
        scopes += config.extraScopes

        let request = OIDAuthorizationRequest(
            configuration: serviceConfig,
            clientId: config.clientID,
            clientSecret: config.clientSecret,
            scopes: scopes,
            redirectURL: URL(string: "k8smanager://oidc-callback")!,
            responseType: OIDResponseTypeCode,
            additionalParameters: nil
        )

        // Wrap AppAuth completion-handler callback in a Swift continuation.
        let authResponse: OIDAuthorizationResponse = try await withCheckedThrowingContinuation { cont in
            // Must be called on the main thread — AppAuth's macOS user-agent requires it.
            DispatchQueue.main.async {
                // OIDExternalUserAgentMac is available only on macOS.
                #if os(macOS)
                // OIDExternalUserAgentMac requires a presenting window on macOS 10.15+.
                // The adapter opens the system browser; a nil window is acceptable when
                // the application is not in a windowed context (e.g. CLI / headless test).
                let userAgent: OIDExternalUserAgentMac
                if #available(macOS 10.15, *) {
                    userAgent = OIDExternalUserAgentMac(presenting: NSApp.mainWindow ?? NSWindow())
                } else {
                    userAgent = OIDExternalUserAgentMac()
                }
                OIDAuthorizationService.present(
                    request,
                    externalUserAgent: userAgent
                ) { response, error in
                    if let response {
                        cont.resume(returning: response)
                    } else {
                        cont.resume(
                            throwing: OIDCAdapterError.interactiveFailed(
                                detail: error?.localizedDescription ?? "Unknown AppAuth error"
                            )
                        )
                    }
                }
                #else
                cont.resume(throwing: OIDCAdapterError.interactiveFailed(detail: "Platform not supported"))
                #endif
            }
        }

        guard let authCode = authResponse.authorizationCode else {
            throw OIDCAdapterError.interactiveFailed(detail: "No authorization code in response")
        }

        let tokenRequest = OIDTokenRequest(
            configuration: serviceConfig,
            grantType: OIDGrantTypeAuthorizationCode,
            authorizationCode: authCode,
            redirectURL: request.redirectURL,
            clientID: config.clientID,
            clientSecret: config.clientSecret,
            scopes: scopes,
            refreshToken: nil,
            codeVerifier: authResponse.request.codeVerifier,
            additionalParameters: nil
        )

        let tokenResponse: OIDTokenResponse = try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.perform(tokenRequest) { response, error in
                if let response {
                    cont.resume(returning: response)
                } else {
                    cont.resume(
                        throwing: OIDCAdapterError.interactiveFailed(
                            detail: error?.localizedDescription ?? "Token exchange failed"
                        )
                    )
                }
            }
        }

        guard let idToken = tokenResponse.idToken else {
            throw OIDCAdapterError.interactiveFailed(detail: "No id_token in token response")
        }

        let exp = try? expiry(from: idToken)
        await tokenStore.store(
            idToken: idToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: exp,
            for: config.idpIssuerURL,
            clientID: config.clientID
        )
        logger.info("OIDC: interactive authorization-code flow succeeded")
        return idToken
    }

    // MARK: Private — JWT helpers

    /// Verifies the id-token signature against the issuer's JWKS. Returns `true`
    /// only when the token is both structurally valid and not expired.
    private func isValidIDToken(_ token: String, issuerURL: URL) async -> Bool {
        do {
            let discovery = try await discoveryClient.fetchDiscovery(issuerURL: issuerURL)
            let jwksData = try await discoveryClient.fetchJWKS(jwksURI: discovery.jwksUri)
            let jwks = try JSONDecoder().decode(JWKS.self, from: jwksData)
            let keys = JWTKeyCollection()
            try await keys.add(jwks: jwks)
            _ = try await keys.verify(token, as: OIDCIDTokenPayload.self)
            return true
        } catch {
            logger.debug("OIDC: id-token validation failed", metadata: ["error": "\(error)"])
            return false
        }
    }

    /// Extracts the `exp` timestamp from an id-token without signature verification.
    ///
    /// Used only to seed the token-store TTL; the full verification happens in
    /// `isValidIDToken(_:issuerURL:)`.
    private func expiry(from token: String) throws -> Date {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else {
            throw OIDCAdapterError.tokenVerificationFailed(detail: "Malformed JWT")
        }
        var payload = String(parts[1])
        // Base64url → base64 padding
        let remainder = payload.count % 4
        if remainder != 0 { payload += String(repeating: "=", count: 4 - remainder) }
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let payloadData = Data(base64Encoded: payload) else {
            throw OIDCAdapterError.tokenVerificationFailed(detail: "Base64 decode failed")
        }
        struct MinimalClaims: Decodable { let exp: TimeInterval? }
        let claims = try JSONDecoder().decode(MinimalClaims.self, from: payloadData)
        guard let exp = claims.exp else {
            throw OIDCAdapterError.tokenVerificationFailed(detail: "No exp claim")
        }
        return Date(timeIntervalSince1970: exp)
    }

    // MARK: Private — token response parsing

    private struct TokenResponseBody: Decodable {
        let idToken: String?
        let accessToken: String?
        let refreshToken: String?

        private enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    private func parseTokenResponse(_ data: Data) throws -> TokenResponseBody {
        do {
            return try JSONDecoder().decode(TokenResponseBody.self, from: data)
        } catch {
            throw OIDCAdapterError.refreshFailed(
                detail: "Cannot parse token response: \(error.localizedDescription)"
            )
        }
    }
}
