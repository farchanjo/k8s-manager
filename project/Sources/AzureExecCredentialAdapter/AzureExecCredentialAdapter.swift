// AzureExecCredentialAdapter.swift — infrastructure adapter
// Bounded context: cluster_connectivity (adapter layer)
// DDD role: Outbound adapter implementing ExecPluginPort for AKS / Entra ID
// ADR-0018 §Azure/AKS authentication protocol
// ADR-0019 Tier B import: MSAL ObjC callbacks wrapped inside actor isolation.
//
// MSAL version: AzureAD/microsoft-authentication-library-for-objc 2.11.0
// Token scope:  6dae42f8-4368-4678-94ff-3960e28e3630/.default  (AKS audience)
//
// API surface reality (iOS/macOS MSAL ObjC SDK):
//  - MSALPublicClientApplication  — user-account flows (interactive, silent).
//  - No MSALConfidentialClientApplication in this SDK variant.
//  - Service-principal (client-secret / certificate) flows go through the
//    OAuth2 client-credentials grant endpoint directly via URLSession.
@preconcurrency import MSAL
import CryptoKit
import Foundation
import ClusterConnectivity
import SharedKernel
import Logging

// MARK: - AzureExecCredentialAdapter

/// Resolves AKS bearer tokens via MSAL (user accounts) or the OAuth2
/// client-credentials grant endpoint (service principals), without invoking
/// any subprocess.
///
/// Implements ``ExecPluginPort`` for kubeconfig entries whose exec command
/// is `kubelogin` (mapped in the adapter registry per ADR-0018 §Registry).
///
/// ## Flow selection
///
/// Config keys consumed from `auth.env` (kubeconfig exec env block):
/// - `AZURE_TENANT_ID` / `tenantId` — required.
/// - `AZURE_CLIENT_ID` / `clientId` — required.
/// - `AZURE_CLIENT_SECRET` / `clientSecret` — triggers service-principal secret flow.
/// - `AZURE_CERTIFICATE_PATH` / `certificatePath` — triggers service-principal
///   certificate flow (P12/PEM). When both secret and certificate are present,
///   secret takes priority.
///
/// When neither is present, the user-account interactive flow is used: MSAL
/// checks the Keychain cache first; on miss, it falls through to a browser-
/// based interactive sign-in via `MSALPublicClientApplication`.
///
/// ## Thread safety
///
/// All mutable state is confined inside this `actor`. MSAL completion
/// callbacks cross actor boundaries via `withCheckedThrowingContinuation`,
/// satisfying the `@preconcurrency` Tier B contract (ADR-0019).
public actor AzureExecCredentialAdapter: ExecPluginPort {

    // MARK: Constants

    /// AKS audience scope used for all token requests.
    static let aksScope = "6dae42f8-4368-4678-94ff-3960e28e3630/.default"

    // MARK: Stored state (actor-isolated)

    private let logger: Logger
    private let urlSession: URLSession
    /// Cache keyed by `"\(tenantId)/\(clientId)"` — avoids re-initialising
    /// MSALPublicClientApplication on every token refresh.
    private var publicClientCache: [String: MSALPublicClientApplication] = [:]

    // MARK: Init

    /// Creates an adapter instance.
    ///
    /// - Parameters:
    ///   - logger: `swift-log` logger; defaults to a labelled instance.
    ///   - urlSession: URLSession used for the OAuth2 client-credentials grant.
    ///     Defaults to a dedicated ephemeral session.
    public init(
        logger: Logger = Logger(label: "azure-exec-credential-adapter"),
        urlSession: URLSession = URLSession(configuration: .ephemeral)
    ) {
        self.logger = logger
        self.urlSession = urlSession
    }

    // MARK: ExecPluginPort

    /// Acquires an AKS bearer token and returns it wrapped in `AuthInfo`.
    ///
    /// - Parameter auth: Exec-plugin invocation parameters from the kubeconfig.
    /// - Returns: ``AuthInfo/bearerToken(_:)`` containing the access token.
    /// - Throws: ``ExecPluginError`` on auth failure, missing config keys, or
    ///   JSON parse errors.
    public func resolve(auth: ExecPluginAuth) async throws -> AuthInfo {
        let config = envDictionary(from: auth.env)

        guard let tenantId = config["AZURE_TENANT_ID"] ?? config["tenantId"],
              !tenantId.isEmpty else {
            throw ExecPluginError.parseError(
                detail: "Missing required tenantId in exec env (key: AZURE_TENANT_ID or tenantId)"
            )
        }
        guard let clientId = config["AZURE_CLIENT_ID"] ?? config["clientId"],
              !clientId.isEmpty else {
            throw ExecPluginError.parseError(
                detail: "Missing required clientId in exec env (key: AZURE_CLIENT_ID or clientId)"
            )
        }

        let clientSecret = config["AZURE_CLIENT_SECRET"] ?? config["clientSecret"]
        let certificatePath = config["AZURE_CERTIFICATE_PATH"] ?? config["certificatePath"]

        let selector = AzureAuthFlowSelector(
            tenantId: tenantId,
            clientId: clientId,
            clientSecret: clientSecret,
            certificatePath: certificatePath
        )
        let flow = selector.resolve()

        logger.debug(
            "Azure flow selected",
            metadata: [
                "tenantId": "\(tenantId)",
                "clientId": "\(clientId)",
                "flow": "\(flow)"
            ]
        )

        let token = try await acquireToken(
            flow: flow,
            tenantId: tenantId,
            clientId: clientId
        )

        return .bearerToken(BearerTokenAuth(token: token))
    }

    // MARK: Token dispatch

    private func acquireToken(
        flow: AzureAuthFlow,
        tenantId: String,
        clientId: String
    ) async throws -> String {
        switch flow {
        case .servicePrincipalSecret(let clientSecret):
            return try await acquireViaClientCredentialsGrant(
                tenantId: tenantId,
                clientId: clientId,
                clientSecret: clientSecret
            )
        case .servicePrincipalCertificate(let certificatePath):
            return try await acquireViaCertificateGrant(
                tenantId: tenantId,
                clientId: clientId,
                certificatePath: certificatePath
            )
        case .deviceCode:
            return try await acquireViaUserAccount(
                tenantId: tenantId,
                clientId: clientId
            )
        }
    }

    // MARK: Service-principal — client secret (OAuth2 client-credentials grant)

    /// Calls the Entra ID `/token` endpoint with the client-credentials grant
    /// using a client secret.  MSAL iOS/macOS does not expose a confidential
    /// client API; the grant is performed via URLSession directly.
    private func acquireViaClientCredentialsGrant(
        tenantId: String,
        clientId: String,
        clientSecret: String
    ) async throws -> String {
        let tokenURL = try entraTokenURL(tenantId: tenantId)

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "scope", value: Self.aksScope),
        ]
        guard let bodyData = body.percentEncodedQuery?.data(using: .utf8) else {
            throw ExecPluginError.parseError(
                detail: "Failed to URL-encode client-credentials grant body"
            )
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        return try await performTokenRequest(request)
    }

    // MARK: Service-principal — certificate (JWT assertion + client-credentials)

    /// Builds a client-assertion JWT signed with the certificate at
    /// `certificatePath`, then exchanges it for an access token via the
    /// Entra ID `/token` endpoint using the `urn:ietf:params:oauth:client-assertion-type:jwt-bearer`
    /// grant type.
    ///
    /// The certificate file must be a PKCS12 bundle (.p12 / .pfx) containing
    /// both the leaf certificate and the private key.
    private func acquireViaCertificateGrant(
        tenantId: String,
        clientId: String,
        certificatePath: String
    ) async throws -> String {
        let certURL = URL(fileURLWithPath: certificatePath)
        let certData = try Data(contentsOf: certURL)

        // Import the PKCS12 identity.
        let identity = try importPKCS12Identity(certData: certData, path: certificatePath)

        // Retrieve the leaf certificate and private key.
        var leafCertificate: SecCertificate?
        var privateKey: SecKey?
        SecIdentityCopyCertificate(identity, &leafCertificate)
        SecIdentityCopyPrivateKey(identity, &privateKey)

        guard let certificate = leafCertificate, let key = privateKey else {
            throw ExecPluginError.parseError(
                detail: "Failed to extract certificate or private key from PKCS12 at \(certificatePath)"
            )
        }

        // Compute the SHA-1 thumbprint (x5t) of the certificate.
        guard let certData2 = SecCertificateCopyData(certificate) as Data? else {
            throw ExecPluginError.parseError(detail: "Cannot read certificate DER data")
        }
        let thumbprint = sha1Base64URL(certData2)

        // Build client-assertion JWT header + payload.
        let tokenURL = try entraTokenURL(tenantId: tenantId)
        let now = Date()
        let exp = now.addingTimeInterval(300) // 5-minute window
        let jwtHeader = #"{"alg":"RS256","typ":"JWT","x5t":"\#(thumbprint)"}"#
        let jwtPayload = """
        {"iss":"\(clientId)","sub":"\(clientId)","aud":"\(tokenURL.absoluteString)",\
        "jti":"\(UUID().uuidString)","nbf":\(Int(now.timeIntervalSince1970)),\
        "exp":\(Int(exp.timeIntervalSince1970))}
        """
        let headerB64 = base64URLEncode(Data(jwtHeader.utf8))
        let payloadB64 = base64URLEncode(Data(jwtPayload.utf8))
        let signingInput = "\(headerB64).\(payloadB64)"

        // Sign with the private key using RS256.
        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &signError
        ) as Data? else {
            let detail = signError.map { "\($0.takeRetainedValue())" } ?? "unknown"
            throw ExecPluginError.parseError(
                detail: "RS256 signing failed: \(detail)"
            )
        }
        let sigB64 = base64URLEncode(signature)
        let jwt = "\(signingInput).\(sigB64)"

        // Exchange the assertion for a token.
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "grant_type", value: "client_credentials"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(
                name: "client_assertion_type",
                value: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
            ),
            URLQueryItem(name: "client_assertion", value: jwt),
            URLQueryItem(name: "scope", value: Self.aksScope),
        ]
        guard let bodyData = body.percentEncodedQuery?.data(using: .utf8) else {
            throw ExecPluginError.parseError(
                detail: "Failed to URL-encode certificate-assertion grant body"
            )
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        return try await performTokenRequest(request)
    }

    // MARK: User account — MSAL interactive / silent

    /// Acquires a token for the signed-in user account via MSAL.
    ///
    /// Attempts silent token acquisition first (MSAL Keychain cache). If no
    /// cached account exists, logs a `info`-level message: interactive sign-in
    /// requires a UI window and cannot be triggered headlessly from this
    /// non-isolated context. The caller is expected to surface an appropriate
    /// error or retry via the application UI.
    private func acquireViaUserAccount(
        tenantId: String,
        clientId: String
    ) async throws -> String {
        let app = try publicClientApplication(tenantId: tenantId, clientId: clientId)

        // Enumerate cached accounts (MSAL Keychain).
        // Swift bridges -allAccounts: (NSError **) → throws, taking no arguments.
        let accounts = try? app.allAccounts()

        if let firstAccount = accounts?.first {
            let silentParams = MSALSilentTokenParameters(
                scopes: [Self.aksScope],
                account: firstAccount
            )

            return try await withCheckedThrowingContinuation { continuation in
                app.acquireTokenSilent(with: silentParams) { result, error in
                    if let error {
                        continuation.resume(throwing: ExecPluginError.parseError(
                            detail: "MSAL silent token error: \(error.localizedDescription)"
                        ))
                        return
                    }
                    guard let token = result?.accessToken, !token.isEmpty else {
                        continuation.resume(throwing: ExecPluginError.parseError(
                            detail: "MSAL returned empty access token (silent flow)"
                        ))
                        return
                    }
                    continuation.resume(returning: token)
                }
            }
        }

        // No cached account — interactive sign-in cannot be triggered here
        // without a presenting NSWindow. Surface a descriptive error so the
        // application layer can initiate the interactive flow on the main actor.
        logger.info(
            "No MSAL cached account found",
            metadata: [
                "tenantId": "\(tenantId)",
                "clientId": "\(clientId)",
                "hint": "Trigger MSALPublicClientApplication.acquireToken on @MainActor with MSALWebviewParameters"
            ]
        )
        throw ExecPluginError.parseError(
            detail: "No cached MSAL account for tenantId=\(tenantId) clientId=\(clientId). "
                + "Run interactive sign-in first (device-code or browser flow) to populate the Keychain cache."
        )
    }

    // MARK: MSAL application factory

    private func publicClientApplication(
        tenantId: String,
        clientId: String
    ) throws -> MSALPublicClientApplication {
        let cacheKey = "\(tenantId)/\(clientId)"
        if let cached = publicClientCache[cacheKey] {
            return cached
        }
        let authority = try msalAuthority(tenantId: tenantId)
        let config = MSALPublicClientApplicationConfig(
            clientId: clientId,
            redirectUri: nil,
            authority: authority
        )
        let app = try MSALPublicClientApplication(configuration: config)
        publicClientCache[cacheKey] = app
        return app
    }

    // MARK: URLSession token request (service principal flows)

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
    }

    private func performTokenRequest(_ request: URLRequest) async throws -> String {
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExecPluginError.parseError(detail: "Non-HTTP response from Entra ID token endpoint")
        }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw ExecPluginError.parseError(
                detail: "Entra ID token endpoint returned HTTP \(httpResponse.statusCode): \(body)"
            )
        }

        do {
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard !tokenResponse.access_token.isEmpty else {
                throw ExecPluginError.parseError(
                    detail: "Entra ID returned an empty access_token"
                )
            }
            return tokenResponse.access_token
        } catch let decodeError as ExecPluginError {
            throw decodeError
        } catch {
            throw ExecPluginError.parseError(
                detail: "Failed to decode Entra ID token response: \(error.localizedDescription)"
            )
        }
    }

    // MARK: Authority URL helper

    private func entraTokenURL(tenantId: String) throws -> URL {
        let urlString = "https://login.microsoftonline.com/\(tenantId)/oauth2/v2.0/token"
        guard let url = URL(string: urlString) else {
            throw ExecPluginError.parseError(
                detail: "Invalid Entra ID token URL for tenantId '\(tenantId)'"
            )
        }
        return url
    }

    private func msalAuthority(tenantId: String) throws -> MSALAuthority {
        guard let authorityURL = URL(string: "https://login.microsoftonline.com/\(tenantId)") else {
            throw ExecPluginError.parseError(
                detail: "Invalid authority URL for tenantId '\(tenantId)'"
            )
        }
        return try MSALAuthority(url: authorityURL)
    }

    // MARK: PKCS12 import helper

    private func importPKCS12Identity(certData: Data, path: String) throws -> SecIdentity {
        // Try importing with an empty passphrase first; if that fails the
        // operator must supply the passphrase via an app-level credential store.
        let options: [String: Any] = [kSecImportExportPassphrase as String: ""]
        var items: CFArray?
        let status = SecPKCS12Import(certData as CFData, options as CFDictionary, &items)

        guard status == errSecSuccess,
              let itemArray = items as? [[String: AnyObject]],
              let firstItem = itemArray.first,
              let rawIdentity = firstItem[kSecImportItemIdentity as String] else {
            throw ExecPluginError.parseError(
                detail: "Cannot import PKCS12 identity from \(path) (status=\(status)). "
                    + "Ensure the file is a valid PKCS12 bundle with an empty passphrase."
            )
        }

        // swiftlint:disable:next force_cast
        return rawIdentity as! SecIdentity
    }

    // MARK: Crypto helpers

    /// Returns the SHA-1 digest of `data` encoded as base64url (no padding).
    /// Used for the certificate thumbprint (`x5t`) in the client-assertion JWT header.
    private func sha1Base64URL(_ data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return base64URLEncode(Data(digest))
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: env → dictionary

    /// Converts the flat `[EnvVar]` from `ExecPluginAuth` into a keyed
    /// dictionary. Later entries with the same key win (last-write semantics).
    private func envDictionary(from envVars: [EnvVar]) -> [String: String] {
        envVars.reduce(into: [:]) { dict, envVar in
            dict[envVar.name] = envVar.value
        }
    }
}
