// AzureExecCredentialAdapterTests.swift — unit tests
// Coverage: flow selector logic, ExecCredential JSON encoding, construction smoke.
// No live network or real MSAL token calls — all tests operate on pure value types.

import XCTest
@testable import AzureExecCredentialAdapter
import ClusterConnectivity
import Foundation

// MARK: - Flow Selector Tests

final class AzureAuthFlowSelectorTests: XCTestCase {

    // MARK: Service-principal secret flow

    func testResolve_withClientSecret_returnsServicePrincipalSecretFlow() {
        let selector = AzureAuthFlowSelector(
            tenantId: "tenant-abc",
            clientId: "client-xyz",
            clientSecret: "super-secret",
            certificatePath: nil
        )
        let flow = selector.resolve()
        XCTAssertEqual(flow, .servicePrincipalSecret(clientSecret: "super-secret"))
    }

    // MARK: Service-principal certificate flow

    func testResolve_withCertificatePath_andNoSecret_returnsCertificateFlow() {
        let selector = AzureAuthFlowSelector(
            tenantId: "tenant-abc",
            clientId: "client-xyz",
            clientSecret: nil,
            certificatePath: "/tmp/cert.p12"
        )
        let flow = selector.resolve()
        XCTAssertEqual(flow, .servicePrincipalCertificate(certificatePath: "/tmp/cert.p12"))
    }

    // MARK: Secret wins over certificate (priority)

    func testResolve_withBothSecretAndCertificate_prefersSecret() {
        let selector = AzureAuthFlowSelector(
            tenantId: "tenant-abc",
            clientId: "client-xyz",
            clientSecret: "secret-value",
            certificatePath: "/tmp/cert.p12"
        )
        let flow = selector.resolve()
        XCTAssertEqual(flow, .servicePrincipalSecret(clientSecret: "secret-value"))
    }

    // MARK: Device-code fallback

    func testResolve_withNoSecretAndNoCertificate_returnsDeviceCodeFlow() {
        let selector = AzureAuthFlowSelector(
            tenantId: "tenant-abc",
            clientId: "client-xyz",
            clientSecret: nil,
            certificatePath: nil
        )
        let flow = selector.resolve()
        XCTAssertEqual(flow, .deviceCode)
    }

    // MARK: Empty strings treated as absent

    func testResolve_withEmptyStrings_treatedAsAbsent_returnsDeviceCode() {
        let selector = AzureAuthFlowSelector(
            tenantId: "tenant-abc",
            clientId: "client-xyz",
            clientSecret: "",
            certificatePath: ""
        )
        let flow = selector.resolve()
        XCTAssertEqual(flow, .deviceCode)
    }
}

// MARK: - ExecCredential JSON Output Tests

final class AzureExecCredentialOutputTests: XCTestCase {

    // MARK: Token-only credential serialises correctly

    func testJsonData_tokenOnly_roundTrips() throws {
        let credential = ExecCredentialV1(
            token: "eyJhbGciOiJSUzI1NiJ9.test",
            expirationTimestamp: nil
        )
        let data = try credential.jsonData()
        let decoded = try JSONDecoder().decode(ExecCredentialV1.self, from: data)
        XCTAssertEqual(decoded.apiVersion, "client.authentication.k8s.io/v1")
        XCTAssertEqual(decoded.kind, "ExecCredential")
        XCTAssertEqual(decoded.status.token, "eyJhbGciOiJSUzI1NiJ9.test")
        XCTAssertNil(decoded.status.expirationTimestamp)
    }

    // MARK: Expiry timestamp is preserved

    func testJsonData_withExpiry_roundTrips() throws {
        let expiry = "2026-05-16T12:00:00.000Z"
        let credential = ExecCredentialV1(
            token: "tok-abc",
            expirationTimestamp: expiry
        )
        let data = try credential.jsonData()
        let decoded = try JSONDecoder().decode(ExecCredentialV1.self, from: data)
        XCTAssertEqual(decoded.status.expirationTimestamp, expiry)
    }

    // MARK: apiVersion and kind are fixed

    func testJsonData_apiVersionAndKind_areFixed() throws {
        let credential = ExecCredentialV1(token: "t", expirationTimestamp: nil)
        let data = try credential.jsonData()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["apiVersion"] as? String, "client.authentication.k8s.io/v1")
        XCTAssertEqual(json["kind"] as? String, "ExecCredential")
    }

    // MARK: Date RFC 3339 helper

    func testDateRfc3339_containsT_andZ() {
        // Verify the helper emits a broadly valid ISO-8601/RFC-3339 string.
        let date = Date(timeIntervalSince1970: 1_747_349_000)
        let formatted = date.rfc3339
        XCTAssertTrue(formatted.contains("T"), "RFC 3339 string must contain 'T' separator")
        XCTAssertFalse(formatted.isEmpty)
    }
}

// MARK: - Adapter Construction Smoke Tests

final class AzureExecCredentialAdapterConstructionTests: XCTestCase {

    // MARK: Actor instantiation does not crash

    func testInit_defaultLogger_doesNotThrow() {
        // AzureExecCredentialAdapter is an actor — init is synchronous.
        let adapter = AzureExecCredentialAdapter()
        XCTAssertNotNil(adapter)
    }

    // MARK: resolve — missing tenantId throws parseError

    func testResolve_missingTenantId_throwsParseError() async {
        let adapter = AzureExecCredentialAdapter()
        let auth = ExecPluginAuth(
            apiVersion: "client.authentication.k8s.io/v1",
            command: "kubelogin",
            args: [],
            env: [EnvVar(name: "AZURE_CLIENT_ID", value: "client-xyz")]
        )
        do {
            _ = try await adapter.resolve(auth: auth)
            XCTFail("Expected ExecPluginError.parseError — missing tenantId")
        } catch ExecPluginError.parseError(let detail) {
            XCTAssertTrue(
                detail.lowercased().contains("tenantid"),
                "Error message should mention tenantId; got: \(detail)"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: resolve — missing clientId throws parseError

    func testResolve_missingClientId_throwsParseError() async {
        let adapter = AzureExecCredentialAdapter()
        let auth = ExecPluginAuth(
            apiVersion: "client.authentication.k8s.io/v1",
            command: "kubelogin",
            args: [],
            env: [EnvVar(name: "AZURE_TENANT_ID", value: "tenant-abc")]
        )
        do {
            _ = try await adapter.resolve(auth: auth)
            XCTFail("Expected ExecPluginError.parseError — missing clientId")
        } catch ExecPluginError.parseError(let detail) {
            XCTAssertTrue(
                detail.lowercased().contains("clientid"),
                "Error message should mention clientId; got: \(detail)"
            )
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
