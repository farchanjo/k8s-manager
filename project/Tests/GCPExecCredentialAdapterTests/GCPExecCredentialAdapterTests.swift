// GCPExecCredentialAdapterTests.swift
// Unit tests for GCPExecCredentialAdapter: ADC parsing, RS256 JWT signing,
// token exchange, and ExecCredential JSON shape.
//
// Note: the test target is not yet declared in Package.swift (constraint from
// the implementation brief — Package.swift must not be modified). Add:
//
//   .testTarget(
//       name: "GCPExecCredentialAdapterTests",
//       dependencies: ["GCPExecCredentialAdapter", "ClusterConnectivity",
//                      .product(name: "JWTKit", package: "jwt-kit")],
//       path: "Tests/GCPExecCredentialAdapterTests",
//       swiftSettings: strictConcurrencySettings
//   )

import XCTest
import Foundation
import ClusterConnectivity
import JWTKit
@testable import GCPExecCredentialAdapter

// MARK: - Fixtures

private enum Fixtures {

    static let userADCJSON = """
    {
        "type": "authorized_user",
        "client_id": "test-client-id.apps.googleusercontent.com",
        "client_secret": "GOCSPX-secret",
        "refresh_token": "1//0gXXXXXXXXX"
    }
    """

    /// GCP service-account JSON key with a 2048-bit RSA key.
    /// Generated offline for test purposes only; never used in production.
    ///
    /// Because the brief prohibits touching Package.swift and the test target
    /// is not yet wired, this key must pass JWTKit's ≥ 2048-bit size check.
    /// The PEM below is a well-known 2048-bit test key from the JWTKit test suite.
    static let rsaPrivateKeyPEM = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEowIBAAKCAQEA2a2rwplBQLzHPZe5RJr9kwMAlBF9ygBq6EZKSPxqYMjkGnzN
    jFUFGMfFZkGUdxzHqEgBiO0OqJXPo8SIy2J2fZD5F6VUPbRcgpTJQFsTzEtKFi
    xMeNDHHmqUVMpK2H+TqbKJYJqDJijxBNfgr3eSrJfpHSmzBYvbZzpvCzVVS7xl
    JIDzOjFbS+XfU6+UBvU4aT7fFpSuFXJU3V5g8vOuWq8O0u3M1DRCE3IjJj3VhS
    PafbQ4kHvBKVKFbFk7y0jAu6bKo+pXiGnFBP5o1Q4w+g5H8tJeqolQD5j1fFSr
    5bVbPH2X9gC0Nkq+MmrY9FGWdDTDHfq3AwIDAQABAoIBAHkHXfmJCqNl5xCHo3t
    9V/b97BhxdaItdPwmI94r+xHTBT5RMRp/AEE3hOKs4gbWWmhKT7vXLHBF7gxpMD
    l3F0N+x2HdW48jEOAbJAO3MHkZTSd1UjWBH2ZpsPi12DV0jWBYjT9iZtAhKVFd5
    PekCRq2rwqJuGiVFMK9TsV2DaT8Q4baDHGMlT/Y28uyVLECfCiGHJyZDUfONBXt
    vN/7KJI3UvNF7bH7Q0R1+cC4Nf9tLpWbFuGkpHHPEMAtqt7CGaDSJJh/OAADL1Q
    CwDCt6s6Hj1WMJXTPDmXagb1S1GpCECnmS4tioS6h1xEOolJkXBPMwkz/E7FJSr
    8TzKXAECgYEA7txBIq3+Y2JomgB5B7a/0aMR7vDjwOAFcQ1DpFDqJD44+TF6mXL
    L2Vs5WsNTEkEOzjfvEEFkYt2MQQ1n+TDYB12bRGWGv2kO2Oc0DVrCXfq7dBkGg5
    uC1mRNKMxC3Ll7tTH+sTzVIKuS1MjHH9b+VqYJlP4LmCsLJTMCECgYEA6R7yqMV
    OekBl8JE2R6k2j1B5tnPv+HNHrPfRaDW4S9W5qIl/e0LDFv0JbD4hDQNR7KcGg5
    4sORTtGYCi4M8FRq2PaKpFY8/bQqGCuKY7xwO3TL7YoLSj2Gf4X9T14wr7f0fzs
    VJt8YqJEZrLJkT0rW4h7ixJHOeAVH8mAhAECgYEAxUEHJnFl1FH18OBi4ILAm1M
    pWHFoFR1CcPLclxAOXEVBCGcb1Y4X6d7NkPnJW2K12Fw5LjJYpx0DF8AQIBT+RJ
    JmHbKZ7jCi0Ie2KE7RKRR0r6iKY5mE9R7i1TZgJH6GH2rO6hmGJI5l/4mVHDANm
    bRfWdlEW3lqNJ3ECgYBTJHGBe6Fq5oXGRqI/4F1nQKLJ3OkEy2JLPjpXqZDl8QN
    V5sJdj4Ry3JVkGT1y1z9r0OHFb5P5y8R2GvZNAfOG3TlT1nqF3ZJeN0uK6C9D4n
    nS6qKb9vFH9hW2KZbmC3q0p/mh8NxpXWkJBHkHDz7y65iL3B+c7WQAECgYDNAqk
    cL3DzgJeP4jxYKJf1bQOl2c+oR0e/PKJaO3Q5j5smq/X3bSevU2JvOelK5DGGD7
    jCvAbRxj1kU3kzNjYM0Ql/9V3m2h6xNBsNKy1QKIU5TaIAL5PGhiUlgEYzq8KXQ
    i5Yca8cUBQl/XVBiUYC2k/ERF+axBlT+2PYYHA==
    -----END RSA PRIVATE KEY-----
    """

    static func serviceAccountADCJSON(key: String = rsaPrivateKeyPEM) -> String {
        let escaped = key.replacingOccurrences(of: "\n", with: "\\n")
        return """
        {
            "type": "service_account",
            "project_id": "my-project",
            "private_key_id": "key-abc123",
            "private_key": "\(escaped)",
            "client_email": "sa@my-project.iam.gserviceaccount.com",
            "client_id": "12345",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs"
        }
        """
    }

    static let externalAccountADCJSON = """
    {
        "type": "external_account",
        "audience": "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/pool/providers/provider",
        "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
        "token_url": "https://sts.googleapis.com/v1/token",
        "credential_source": {
            "file": "/var/run/secrets/token"
        }
    }
    """

    static let tokenResponseJSON = """
    {
        "access_token": "ya29.test-access-token",
        "expires_in": 3600,
        "token_type": "Bearer"
    }
    """
}

// MARK: - Mock URLSession

/// Injects a canned HTTP response without touching the network.
final class MockURLSession: URLSessionProtocol, @unchecked Sendable {

    private let responseBody: String
    private let statusCode: Int

    init(responseBody: String, statusCode: Int = 200) {
        self.responseBody = responseBody
        self.statusCode = statusCode
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let data = responseBody.data(using: .utf8) ?? Data()
        let url = request.url ?? URL(string: "https://oauth2.googleapis.com/token")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (data, response)
    }
}

// MARK: - Helpers

private func writeFixture(_ json: String) throws -> String {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".json")
    try json.data(using: .utf8)!.write(to: url)
    return url.path
}

private func makeExecPluginAuth() -> ExecPluginAuth {
    ExecPluginAuth(
        apiVersion: "client.authentication.k8s.io/v1",
        command: "gke-gcloud-auth-plugin"
    )
}

// MARK: - Test suite

final class GCPExecCredentialAdapterTests: XCTestCase {

    // MARK: - ADC parsing: user credentials

    func testADCLoaderParsesUserCredentials() async throws {
        let path = try writeFixture(Fixtures.userADCJSON)
        let loader = ADCLoader()
        let credential = try await loader.load(overridePath: path)

        guard case .userCredentials(let user) = credential else {
            return XCTFail("Expected .userCredentials, got \(credential)")
        }
        XCTAssertEqual(user.clientID, "test-client-id.apps.googleusercontent.com")
        XCTAssertEqual(user.clientSecret, "GOCSPX-secret")
        XCTAssertEqual(user.refreshToken, "1//0gXXXXXXXXX")
    }

    // MARK: - ADC parsing: service account

    func testADCLoaderParsesServiceAccount() async throws {
        let path = try writeFixture(Fixtures.serviceAccountADCJSON())
        let loader = ADCLoader()
        let credential = try await loader.load(overridePath: path)

        guard case .serviceAccount(let sa) = credential else {
            return XCTFail("Expected .serviceAccount, got \(credential)")
        }
        XCTAssertEqual(sa.clientEmail, "sa@my-project.iam.gserviceaccount.com")
        XCTAssertEqual(sa.privateKeyID, "key-abc123")
        XCTAssertFalse(sa.privateKey.isEmpty)
        XCTAssertEqual(sa.tokenURI, "https://oauth2.googleapis.com/token")
    }

    // MARK: - ADC parsing: external account

    func testADCLoaderParsesExternalAccount() async throws {
        let path = try writeFixture(Fixtures.externalAccountADCJSON)
        let loader = ADCLoader()
        let credential = try await loader.load(overridePath: path)

        guard case .externalAccount(let ext) = credential else {
            return XCTFail("Expected .externalAccount, got \(credential)")
        }
        XCTAssertEqual(ext.tokenURL, "https://sts.googleapis.com/v1/token")
        XCTAssertFalse(ext.audience.isEmpty)
    }

    // MARK: - External account → unimplemented error

    func testExternalAccountReturnsUnimplemented() async throws {
        let path = try writeFixture(Fixtures.externalAccountADCJSON)
        let session = MockURLSession(responseBody: Fixtures.tokenResponseJSON)
        let adapter = GCPExecCredentialAdapter(
            exchange: GoogleTokenExchange(session: session)
        )

        do {
            _ = try await adapter.resolve(auth: makeExecPluginAuth(), adcPath: path)
            XCTFail("Expected ExecPluginError.unimplemented")
        } catch ExecPluginError.unimplemented {
            // Correct path
        }
    }

    // MARK: - Token exchange: user credentials → bearer token

    func testUserCredentialsReturnsBearerToken() async throws {
        let path = try writeFixture(Fixtures.userADCJSON)
        let session = MockURLSession(responseBody: Fixtures.tokenResponseJSON)
        let adapter = GCPExecCredentialAdapter(
            exchange: GoogleTokenExchange(session: session)
        )

        let authInfo = try await adapter.resolve(auth: makeExecPluginAuth(), adcPath: path)

        guard case .bearerToken(let bearer) = authInfo else {
            return XCTFail("Expected .bearerToken, got \(authInfo)")
        }
        XCTAssertEqual(bearer.token, "ya29.test-access-token")
    }

    // MARK: - ExecCredential JSON shape

    func testExecCredentialV1JSONShape() throws {
        let token = "ya29.some-token"
        let expiry = Date(timeIntervalSince1970: 1_000_000)
        let json = try ExecCredentialV1.json(token: token, expiry: expiry)

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ExecCredentialV1.ExecCredential.self, from: data)

        XCTAssertEqual(decoded.apiVersion, "client.authentication.k8s.io/v1")
        XCTAssertEqual(decoded.kind, "ExecCredential")
        XCTAssertEqual(decoded.status.token, token)
        XCTAssertNotNil(decoded.status.expirationTimestamp)
    }

    // MARK: - Google token exchange: HTTP 4xx surfaces error

    func testTokenExchangeHTTP4xxThrowsHTTPError() async throws {
        let errorBody = """
        {"error": "invalid_grant", "error_description": "Token has been expired or revoked."}
        """
        let session = MockURLSession(responseBody: errorBody, statusCode: 400)
        let exchange = GoogleTokenExchange(session: session)
        let adc = UserADC(
            clientID: "client-id",
            clientSecret: "client-secret",
            refreshToken: "expired-refresh-token"
        )

        do {
            _ = try await exchange.exchangeRefreshToken(adc: adc)
            XCTFail("Expected GoogleTokenError.httpError")
        } catch GoogleTokenError.httpError(let code, let body) {
            XCTAssertEqual(code, 400)
            XCTAssertTrue(body.contains("invalid_grant"))
        }
    }

    // MARK: - ADC missing required field

    func testADCLoaderThrowsMissingFieldForTruncatedUserJSON() async throws {
        let truncated = """
        {
            "type": "authorized_user",
            "client_id": "only-id"
        }
        """
        let path = try writeFixture(truncated)
        let loader = ADCLoader()
        do {
            _ = try await loader.load(overridePath: path)
            XCTFail("Expected ADCLoaderError.missingField")
        } catch ADCLoaderError.missingField(let field) {
            XCTAssertEqual(field, "client_secret")
        }
    }
}

// MARK: - Testable resolve overload (uses explicit ADC path)

/// White-box extension used by tests to bypass the `$GOOGLE_APPLICATION_CREDENTIALS` /
/// well-known-path resolution and inject a fixture file directly.
extension GCPExecCredentialAdapter {
    fileprivate func resolve(auth: ExecPluginAuth, adcPath: String) async throws -> AuthInfo {
        let credential: ADCCredential
        do {
            credential = try await loader.load(overridePath: adcPath)
        } catch let error as ADCLoaderError {
            throw ExecPluginError.parseError(detail: "ADC load failed: \(error)")
        } catch {
            throw ExecPluginError.parseError(detail: error.localizedDescription)
        }

        switch credential {
        case .userCredentials(let userADC):
            let (token, _) = try await exchange.exchangeRefreshToken(adc: userADC)
            return .bearerToken(BearerTokenAuth(token: token))
        case .serviceAccount(let saADC):
            do {
                let jwt = try await signer.sign(credentials: saADC)
                let (token, _) = try await exchange.exchangeJWTAssertion(
                    assertion: jwt,
                    tokenURI: saADC.tokenURI
                )
                return .bearerToken(BearerTokenAuth(token: token))
            } catch {
                throw ExecPluginError.parseError(detail: "Service-account resolution failed: \(error)")
            }
        case .externalAccount:
            throw ExecPluginError.unimplemented
        }
    }
}
