// OIDCExecCredentialAdapterTests.swift — OIDCExecCredentialAdapter test target
// Coverage: discovery JSON parse, JWKS key selection, id-token signature verify
//           with fixture key, refresh-token flow shape, ExecCredential JSON encode.

import Foundation
import JWTKit
import XCTest

@testable import OIDCExecCredentialAdapter

// MARK: - DiscoveryParseTests

/// Validates that `OIDCDiscoveryDocument` decodes standard discovery JSON correctly.
final class DiscoveryParseTests: XCTestCase {

    func test_standard_discovery_document_decodes_all_required_fields() throws {
        let data = Data(discoveryFixture.utf8)
        let doc = try JSONDecoder().decode(OIDCDiscoveryDocument.self, from: data)
        XCTAssertEqual(doc.issuer, "https://accounts.example.com")
        XCTAssertEqual(doc.authorizationEndpoint, "https://accounts.example.com/o/oauth2/v2/auth")
        XCTAssertEqual(doc.tokenEndpoint, "https://accounts.example.com/token")
        XCTAssertEqual(doc.jwksUri, "https://accounts.example.com/.well-known/certs")
    }

    func test_discovery_missing_token_endpoint_throws() {
        let json = """
        {
          "issuer": "https://example.com",
          "authorization_endpoint": "https://example.com/auth",
          "jwks_uri": "https://example.com/certs"
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(OIDCDiscoveryDocument.self, from: Data(json.utf8))
        )
    }

    func test_discovery_extra_fields_are_ignored() throws {
        let json = """
        {
          "issuer": "https://accounts.example.com",
          "authorization_endpoint": "https://accounts.example.com/auth",
          "token_endpoint": "https://accounts.example.com/token",
          "jwks_uri": "https://accounts.example.com/certs",
          "unknown_field_xyz": "ignored",
          "scopes_supported": ["openid", "profile"]
        }
        """
        let doc = try JSONDecoder().decode(OIDCDiscoveryDocument.self, from: Data(json.utf8))
        XCTAssertEqual(doc.issuer, "https://accounts.example.com")
    }
}

// MARK: - JWKSKeySelectionTests

/// Validates JWKS key lookup by `kid` using `JWTKit.JWKS`.
final class JWKSKeySelectionTests: XCTestCase {

    func test_find_key_by_kid_returns_correct_key() throws {
        let data = Data(jwksFixture.utf8)
        let jwks = try JSONDecoder().decode(JWKS.self, from: data)

        let found = jwks.find(identifier: "key-2024-01", type: .rsa)
        XCTAssertNotNil(found, "Expected to find RSA key with kid=key-2024-01")
        XCTAssertEqual(found?.keyIdentifier?.string, "key-2024-01")
    }

    func test_find_key_wrong_kid_returns_nil() throws {
        let data = Data(jwksFixture.utf8)
        let jwks = try JSONDecoder().decode(JWKS.self, from: data)

        let found = jwks.find(identifier: "nonexistent-kid", type: .rsa)
        XCTAssertNil(found)
    }

    func test_jwks_contains_expected_key_count() throws {
        let data = Data(jwksFixture.utf8)
        let jwks = try JSONDecoder().decode(JWKS.self, from: data)
        XCTAssertEqual(jwks.keys.count, 1)
    }
}

// MARK: - IDTokenSignatureTests

/// Verifies id-token signature verification using `JWTKeyCollection` and a
/// fixture HMAC key (HS256 for self-contained test — no RSA keygen required).
final class IDTokenSignatureTests: XCTestCase {

    /// Signs a fixture payload with HS256, then verifies it via `JWTKeyCollection`.
    /// This exercises the same path as the adapter's `isValidIDToken` method.
    func test_valid_id_token_signature_verifies_successfully() async throws {
        let keys = JWTKeyCollection()
        await keys.add(hmac: hs256Secret, digestAlgorithm: .sha256, kid: JWKIdentifier(string: "hs256-test"))

        let payload = FixturePayload(
            sub: "user@example.com",
            iss: "https://accounts.example.com",
            exp: .init(value: Date().addingTimeInterval(3600))
        )
        let token = try await keys.sign(payload, kid: JWKIdentifier(string: "hs256-test"))
        let verified = try await keys.verify(token, as: FixturePayload.self)
        XCTAssertEqual(verified.sub, "user@example.com")
    }

    /// Verifies that a tampered token (wrong signature) is rejected.
    func test_tampered_id_token_signature_fails_verification() async throws {
        let signerKeys = JWTKeyCollection()
        await signerKeys.add(hmac: hs256Secret, digestAlgorithm: .sha256)
        let payload = FixturePayload(
            sub: "user@example.com",
            iss: "https://accounts.example.com",
            exp: .init(value: Date().addingTimeInterval(3600))
        )
        let token = try await signerKeys.sign(payload)

        // Tamper: replace last 6 characters of the signature segment.
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return XCTFail("Expected 3-part JWT") }
        let tampered = "\(parts[0]).\(parts[1]).TAMPERED"

        let verifierKeys = JWTKeyCollection()
        await verifierKeys.add(hmac: hs256Secret, digestAlgorithm: .sha256)

        do {
            _ = try await verifierKeys.verify(tampered, as: FixturePayload.self)
            XCTFail("Expected verification to throw on tampered token")
        } catch {
            // Verification failure is expected — any error satisfies the test.
            XCTAssertNotNil(error)
        }
    }
}

// MARK: - RefreshTokenFlowTests

/// Validates the shape of the refresh-token grant request produced by the
/// adapter by intercepting the URLSession call through a URLProtocol stub.
final class RefreshTokenFlowTests: XCTestCase {

    /// Registers the stub protocol, performs a resolve call, and asserts that
    /// the HTTP request has the correct form-encoded body fields.
    func test_refresh_grant_sends_correct_body_fields() async throws {
        let expectation = expectation(description: "Refresh POST received")
        StubURLProtocol.responseData = refreshTokenResponseData
        StubURLProtocol.requestHandler = { request in
            guard let body = request.httpBody,
                  let bodyString = String(data: body, encoding: .utf8) else {
                return
            }
            let params = URLComponents(string: "?\(bodyString)")?.queryItems ?? []
            let dict = Dictionary(uniqueKeysWithValues: params.compactMap {
                $0.value.map { ($0.name, $0) }
            })
            XCTAssertEqual(dict["grant_type"]?.value, "refresh_token")
            XCTAssertEqual(dict["client_id"]?.value, "test-client")
            XCTAssertEqual(dict["refresh_token"]?.value, "refresh-abc123")
            expectation.fulfill()
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)

        // Seed a discovery document and JWKS response into the stub.
        StubURLProtocol.urlResponses = [
            "https://idp.example.com/.well-known/openid-configuration": Data(discoveryFixture.utf8),
            "https://accounts.example.com/.well-known/certs": Data(jwksFixture.utf8),
            "https://accounts.example.com/token": refreshTokenResponseData,
        ]

        let adapter = OIDCExecCredentialAdapter(session: session)
        let auth = makeExecPluginAuth(
            refreshToken: "refresh-abc123",
            idToken: nil
        )

        // The adapter will fail signature verification of the returned token
        // (stub key does not match fixture JWKS), but the POST shape is what we test.
        _ = try? await adapter.resolve(auth: auth)

        await fulfillment(of: [expectation], timeout: 3)
    }
}

// MARK: - ExecCredentialOutputTests

/// Validates JSON encoding of `ExecCredential` to the Kubernetes wire format.
final class ExecCredentialOutputTests: XCTestCase {

    func test_exec_credential_encodes_bearer_token_correctly() throws {
        let cred = ExecCredential(idToken: "my.id.token", expirationTimestamp: nil)
        let data = try JSONEncoder().encode(cred)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["apiVersion"] as? String, "client.authentication.k8s.io/v1")
        XCTAssertEqual(json?["kind"] as? String, "ExecCredential")
        let status = json?["status"] as? [String: Any]
        XCTAssertEqual(status?["token"] as? String, "my.id.token")
        XCTAssertNil(status?["expirationTimestamp"])
    }

    func test_exec_credential_encodes_expiry_timestamp_as_iso8601() throws {
        let expiry = Date(timeIntervalSince1970: 1_700_000_000)
        let cred = ExecCredential(idToken: "tok", expirationTimestamp: expiry)
        let data = try JSONEncoder().encode(cred)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let status = json?["status"] as? [String: Any]
        let ts = status?["expirationTimestamp"] as? String
        XCTAssertNotNil(ts, "expirationTimestamp should be present")
        // ISO8601 includes the year and ends in Z or offset.
        XCTAssert(ts?.contains("2023") == true || ts?.hasSuffix("Z") == true)
    }

    func test_exec_credential_round_trips_through_decoder() throws {
        let original = ExecCredential(idToken: "round.trip.token", expirationTimestamp: nil)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExecCredential.self, from: encoded)
        XCTAssertEqual(decoded.status.token, "round.trip.token")
        XCTAssertEqual(decoded.apiVersion, "client.authentication.k8s.io/v1")
    }
}

// MARK: - Token store tests

final class OIDCTokenStoreTests: XCTestCase {

    func test_stored_valid_token_is_returned() async {
        let store = OIDCTokenStore()
        await store.store(
            idToken: "id.token.value",
            refreshToken: "refresh.value",
            expiresAt: Date().addingTimeInterval(3600),
            for: "https://idp.example.com",
            clientID: "client"
        )
        let cached = await store.tokens(for: "https://idp.example.com", clientID: "client")
        XCTAssertEqual(cached?.idToken, "id.token.value")
        XCTAssertEqual(cached?.refreshToken, "refresh.value")
        XCTAssertTrue(cached?.isValid() == true)
    }

    func test_expired_token_isValid_returns_false() async {
        let store = OIDCTokenStore()
        await store.store(
            idToken: "expired.token",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(-60),
            for: "https://idp.example.com",
            clientID: "client"
        )
        let cached = await store.tokens(for: "https://idp.example.com", clientID: "client")
        XCTAssertFalse(cached?.isValid() == true)
    }

    func test_invalidate_removes_cached_entry() async {
        let store = OIDCTokenStore()
        await store.store(
            idToken: "token",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(3600),
            for: "https://idp.example.com",
            clientID: "client"
        )
        await store.invalidate(for: "https://idp.example.com", clientID: "client")
        let cached = await store.tokens(for: "https://idp.example.com", clientID: "client")
        XCTAssertNil(cached)
    }
}

// MARK: - Fixture helpers

private let hs256Secret = HMACKey(from: Data("test-secret-key-32-bytes-exactly!!".utf8))

private struct FixturePayload: JWTPayload {
    var sub: String
    var iss: String
    var exp: ExpirationClaim?

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp?.verifyNotExpired()
    }
}

private func makeExecPluginAuth(
    refreshToken: String?,
    idToken: String?
) -> ExecPluginAuth {
    var env: [EnvVar] = [
        EnvVar(name: "OIDC_ISSUER_URL", value: "https://idp.example.com"),
        EnvVar(name: "OIDC_CLIENT_ID", value: "test-client"),
    ]
    if let rt = refreshToken { env.append(EnvVar(name: "OIDC_REFRESH_TOKEN", value: rt)) }
    if let idt = idToken { env.append(EnvVar(name: "OIDC_ID_TOKEN", value: idt)) }
    return ExecPluginAuth(
        apiVersion: "client.authentication.k8s.io/v1",
        command: "oidc-login",
        env: env
    )
}

// MARK: - JSON Fixtures

private let discoveryFixture = """
{
  "issuer": "https://accounts.example.com",
  "authorization_endpoint": "https://accounts.example.com/o/oauth2/v2/auth",
  "token_endpoint": "https://accounts.example.com/token",
  "jwks_uri": "https://accounts.example.com/.well-known/certs",
  "response_types_supported": ["code", "token", "id_token"],
  "subject_types_supported": ["public"],
  "id_token_signing_alg_values_supported": ["RS256"]
}
"""

/// A minimal JWKS with one RSA key (modulus/exponent from the RFC 7517 example).
private let jwksFixture = """
{
  "keys": [
    {
      "kty": "RSA",
      "kid": "key-2024-01",
      "use": "sig",
      "alg": "RS256",
      "n": "pjdss8ZaDfEH6K6U7GeW2nxDqR4IP049fk1fK0lndimbMMVBdPv_hSpm8T8EtBDxrUdi1OHZfMhUixGyw-zF8-tSjVBSAgRzSBrr6bflnYAx9-nFD7Tso3R2t8Uvy9rCO1f7mPDxGe_OJ9-bRuaB_2EF3kCtNQBOXcv0Yz3SbdKAFg7_VaBzgI0WN3TLHFCNRD5GGjX7ZlASXQo6nCM3FnxUChsFZWQSH9hTjFMAvzpKC5Df2-Jtw0JLmimDyQ6Qc7S1f8JBrZqmKJR3p1TLQ8S3gvnEP9TKGWN9c_Bh7Xqmks3tJkGJ3_XEFRN1-fQa_Zk_8QS8c-w",
      "e": "AQAB"
    }
  ]
}
"""

private let refreshTokenResponseData: Data = {
    // The id_token here is a minimal structurally-valid JWT (unsigned/stub) for parse shape only.
    let json = """
    {
      "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6ImtleS0yMDI0LTAxIn0.eyJzdWIiOiJ1c2VyQGV4YW1wbGUuY29tIiwiaXNzIjoiaHR0cHM6Ly9hY2NvdW50cy5leGFtcGxlLmNvbSIsImV4cCI6OTk5OTk5OTk5OX0.stub",
      "access_token": "access-token-value",
      "refresh_token": "new-refresh-token",
      "token_type": "Bearer",
      "expires_in": 3600
    }
    """
    return Data(json.utf8)
}()

// MARK: - StubURLProtocol

/// URLProtocol that intercepts all requests and returns pre-baked fixture data.
private final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    static var urlResponses: [String: Data] = [:]
    static var responseData: Data = Data()
    static var requestHandler: ((URLRequest) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestHandler?(request)

        let urlString = request.url?.absoluteString ?? ""
        let data = Self.urlResponses[urlString] ?? Self.responseData
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
