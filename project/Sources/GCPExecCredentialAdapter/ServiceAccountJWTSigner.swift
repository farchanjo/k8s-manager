// ServiceAccountJWTSigner.swift — GCPExecCredentialAdapter
// Builds and signs a Google OAuth2 JWT assertion for service-account credentials
// using RS256 (RSASSA-PKCS1-v1_5 + SHA-256) via JWTKit's Insecure.RSA API.

import Foundation
import JWTKit
import Logging

// MARK: - ServiceAccountJWTSigner

/// Produces a signed RS256 JWT suitable for the Google OAuth2 token endpoint.
///
/// The JWT follows the Google service-account JWT-bearer grant:
/// - Algorithm: RS256 (PKCS#1 v1.5, SHA-256)
/// - Header: `{"alg":"RS256","typ":"JWT","kid":<keyID>}`
/// - Claims: `iss`, `sub` (= `iss`), `aud`, `scope`, `iat`, `exp` (+3600 s)
///
/// JWTKit requires ≥ 2048-bit RSA keys. GCP service-account JSON keys are
/// always 2048 bits by default, satisfying this constraint in production.
public struct ServiceAccountJWTSigner: Sendable {

    private let logger: Logger

    /// Google OAuth2 token endpoint — audience claim value.
    private static let tokenAudience = "https://oauth2.googleapis.com/token"

    /// GKE/GCP OAuth2 scope required for cluster authentication.
    private static let cloudPlatformScope = "https://www.googleapis.com/auth/cloud-platform"

    public init(logger: Logger = Logger(label: "gcp.jwt-signer")) {
        self.logger = logger
    }

    // MARK: - Public API

    /// Builds and signs a JWT assertion string for `credentials`.
    ///
    /// - Parameter credentials: Parsed service-account ADC fields.
    /// - Returns: Compact-serialised JWT (`header.claims.sig`).
    /// - Throws: `ServiceAccountJWTError` on key-parse or signing failure.
    public func sign(credentials: ServiceAccountADC) async throws -> String {
        // Normalise escaped newlines that GCP JSON embeds as `\n` literals.
        let pemString = credentials.privateKey
            .replacingOccurrences(of: "\\n", with: "\n")

        let rsaKey: Insecure.RSA.PrivateKey
        do {
            rsaKey = try Insecure.RSA.PrivateKey(pem: pemString)
        } catch {
            throw ServiceAccountJWTError.keyParseFailure(detail: error.localizedDescription)
        }

        let collection = JWTKeyCollection()
        let kid = JWKIdentifier(string: credentials.privateKeyID)
        await collection.add(rsa: rsaKey, digestAlgorithm: .sha256, kid: kid)

        let now = Date()
        let expiry = now.addingTimeInterval(3600)

        let payload = GoogleJWTPayload(
            iss: IssuerClaim(value: credentials.clientEmail),
            sub: SubjectClaim(value: credentials.clientEmail),
            aud: AudienceClaim(value: [Self.tokenAudience]),
            scope: Self.cloudPlatformScope,
            iat: IssuedAtClaim(value: now),
            exp: ExpirationClaim(value: expiry)
        )

        do {
            let token = try await collection.sign(payload, kid: kid)
            logger.debug("Signed RS256 JWT for \(credentials.clientEmail), kid=\(credentials.privateKeyID)")
            return token
        } catch {
            throw ServiceAccountJWTError.signingFailure(detail: error.localizedDescription)
        }
    }
}

// MARK: - GoogleJWTPayload

/// JWT claims for a Google service-account assertion.
struct GoogleJWTPayload: JWTPayload {
    var iss: IssuerClaim
    var sub: SubjectClaim
    var aud: AudienceClaim
    var scope: String
    var iat: IssuedAtClaim
    var exp: ExpirationClaim

    func verify(using _: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }
}

// MARK: - ServiceAccountJWTError

/// Errors raised by `ServiceAccountJWTSigner`.
public enum ServiceAccountJWTError: Error, Sendable {
    /// `Insecure.RSA.PrivateKey(pem:)` rejected the key (e.g. < 2048 bits, malformed PEM).
    case keyParseFailure(detail: String)

    /// JWTKit signing operation failed.
    case signingFailure(detail: String)
}
