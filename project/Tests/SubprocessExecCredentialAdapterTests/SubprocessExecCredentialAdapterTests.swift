// SubprocessExecCredentialAdapterTests.swift — SubprocessExecCredentialAdapter test target
// Coverage: allowlist rejection, successful exec, timeout, non-zero exit,
//           malformed stdout, environment injection.
// Test binaries: /bin/echo, /usr/bin/printenv — safe and always present on macOS CI.

import Foundation
import XCTest
import ClusterConnectivity

@testable import SubprocessExecCredentialAdapter

// MARK: - Helpers

/// Builds a minimal `ExecPluginAuth` for testing.
private func makeAuth(
    command: String = "/bin/echo",
    args: [String] = [],
    env: [EnvVar] = []
) -> ExecPluginAuth {
    ExecPluginAuth(
        apiVersion: "client.authentication.k8s.io/v1",
        command: command,
        args: args,
        env: env,
        provideClusterInfo: false
    )
}

/// A valid `client.authentication.k8s.io/v1` bearer-token ExecCredential JSON.
private let bearerTokenFixture = """
{
  "apiVersion": "client.authentication.k8s.io/v1",
  "kind": "ExecCredential",
  "status": {
    "token": "test-token-abc123"
  }
}
"""

/// A valid ExecCredential JSON carrying a client certificate.
private let clientCertFixture = """
{
  "apiVersion": "client.authentication.k8s.io/v1",
  "kind": "ExecCredential",
  "status": {
    "clientCertificateData": "-----BEGIN CERTIFICATE-----\\nMIIBfTCCASKgAwIB\\n-----END CERTIFICATE-----",
    "clientKeyData": "-----BEGIN EC PRIVATE KEY-----\\nMHQCAQEEIA==\\n-----END EC PRIVATE KEY-----"
  }
}
"""

/// JSON that is syntactically valid but carries no usable credential.
private let emptyStatusFixture = """
{
  "apiVersion": "client.authentication.k8s.io/v1",
  "kind": "ExecCredential",
  "status": {}
}
"""

// MARK: - AllowlistTests

/// ADR-0018 + ADR-0033: commands not on the allowlist must be rejected before
/// any subprocess is spawned.
final class AllowlistTests: XCTestCase {

    func test_allowlistRejection_throws_commandNotFound() async {
        let adapter = SubprocessExecCredentialAdapter(
            allowlist: { _ in false }   // deny everything
        )
        let auth = makeAuth(command: "/bin/echo", args: ["hello"])
        do {
            _ = try await adapter.resolve(auth: auth)
            XCTFail("Expected ExecPluginError.commandNotFound")
        } catch ExecPluginError.commandNotFound(let cmd) {
            XCTAssertEqual(cmd, "/bin/echo")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_allowlistAcceptance_does_not_throw_commandNotFound() async {
        // Allowlist permits /bin/echo; produce a valid bearer-token JSON.
        let fixture = bearerTokenFixture
        let adapter = SubprocessExecCredentialAdapter(
            allowlist: { $0 == "/bin/echo" }
        )
        // /bin/echo just prints its args — we use a shell script trick via
        // a temp file to emit real JSON. Since we cannot use shell expansion
        // here, we verify the allowlist does NOT throw commandNotFound; the
        // parse error is acceptable (echo won't emit valid JSON).
        let auth = makeAuth(command: "/bin/echo", args: [fixture])
        do {
            _ = try await adapter.resolve(auth: auth)
            // If somehow the JSON is valid (unlikely from echo formatting), fine.
        } catch ExecPluginError.commandNotFound {
            XCTFail("Allowlist should not reject /bin/echo when permitted")
        } catch {
            // parse / non-zero / etc. are acceptable — we only test allowlist.
        }
    }
}

// MARK: - SuccessfulExecutionTests

/// Tests that a subprocess producing valid ExecCredential JSON resolves to
/// the expected AuthInfo. Uses a temp shell script that emits the fixture.
final class SuccessfulExecutionTests: XCTestCase {

    private func writeTempScript(content: String) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("exec_test_\(UUID().uuidString).sh")
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tmp.path
        )
        return tmp.path
    }

    func test_successfulExecution_bearerToken_resolves() async throws {
        let escapedJSON = bearerTokenFixture
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
        let scriptPath = try writeTempScript(content: "#!/bin/sh\nprintf '\(escapedJSON)'")
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let adapter = SubprocessExecCredentialAdapter(
            allowlist: { $0 == scriptPath }
        )
        let auth = makeAuth(command: scriptPath)
        let resolved = try await adapter.resolve(auth: auth)
        guard case .bearerToken(let bt) = resolved else {
            return XCTFail("Expected .bearerToken, got \(resolved)")
        }
        XCTAssertEqual(bt.token, "test-token-abc123")
    }

    func test_successfulExecution_clientCert_resolves() async throws {
        let escapedJSON = clientCertFixture
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "'\\''")
        let scriptPath = try writeTempScript(content: "#!/bin/sh\nprintf '\(escapedJSON)'")
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }

        let adapter = SubprocessExecCredentialAdapter(
            allowlist: { $0 == scriptPath }
        )
        let auth = makeAuth(command: scriptPath)
        let resolved = try await adapter.resolve(auth: auth)
        guard case .clientCert(let cc) = resolved else {
            return XCTFail("Expected .clientCert, got \(resolved)")
        }
        XCTAssertTrue(cc.certPEM.contains("BEGIN CERTIFICATE"))
        XCTAssertTrue(cc.keyPEM.contains("PRIVATE KEY"))
    }
}

// MARK: - TimeoutTests

/// Validates that a subprocess exceeding the timeout is killed and the adapter
/// throws a recognisable domain error.
final class TimeoutTests: XCTestCase {

    func test_timeout_kills_process_and_throws() async throws {
        // A script that sleeps longer than the timeout window.
        let scriptContent = "#!/bin/sh\nsleep 60\necho '{}'"
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("timeout_test_\(UUID().uuidString).sh")
        try scriptContent.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tmp.path
        )
        defer { try? FileManager.default.removeItem(atPath: tmp.path) }

        let adapter = SubprocessExecCredentialAdapter(
            allowlist: { _ in true },
            timeoutSeconds: 1   // 1-second budget
        )
        let auth = makeAuth(command: tmp.path)
        do {
            _ = try await adapter.resolve(auth: auth)
            XCTFail("Expected error on timeout")
        } catch ExecPluginError.nonZeroExit(let code, let stderr) {
            // Adapter maps timeout → nonZeroExit(code: -1, ...).
            XCTAssertEqual(code, -1)
            XCTAssertTrue(stderr.contains("timeout"), "stderr=\(stderr)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - NonZeroExitTests

/// Validates that a subprocess exiting with a non-zero status code surfaces
/// the exit code and stderr via `ExecPluginError.nonZeroExit`.
final class NonZeroExitTests: XCTestCase {

    func test_nonZeroExit_throws_with_exitCode_and_stderr() async throws {
        let scriptContent = "#!/bin/sh\necho 'something went wrong' >&2\nexit 42"
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("exit42_test_\(UUID().uuidString).sh")
        try scriptContent.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tmp.path
        )
        defer { try? FileManager.default.removeItem(atPath: tmp.path) }

        let adapter = SubprocessExecCredentialAdapter(allowlist: { _ in true })
        let auth = makeAuth(command: tmp.path)
        do {
            _ = try await adapter.resolve(auth: auth)
            XCTFail("Expected ExecPluginError.nonZeroExit")
        } catch ExecPluginError.nonZeroExit(let code, let stderr) {
            XCTAssertEqual(code, 42)
            XCTAssertTrue(stderr.contains("something went wrong"), "stderr=\(stderr)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - MalformedStdoutTests

/// Validates that invalid or credential-free JSON on stdout surfaces as
/// `ExecPluginError.parseError`.
final class MalformedStdoutTests: XCTestCase {

    private func writeTempScript(_ content: String) throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("malformed_\(UUID().uuidString).sh")
        try content.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tmp.path
        )
        return tmp.path
    }

    func test_invalidJSON_stdout_throws_parseError() async throws {
        let path = try writeTempScript("#!/bin/sh\necho 'not-json-at-all'")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let adapter = SubprocessExecCredentialAdapter(allowlist: { _ in true })
        let auth = makeAuth(command: path)
        do {
            _ = try await adapter.resolve(auth: auth)
            XCTFail("Expected ExecPluginError.parseError")
        } catch ExecPluginError.parseError(let detail) {
            XCTAssertFalse(detail.isEmpty)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_emptyStatus_stdout_throws_parseError() async throws {
        let escaped = emptyStatusFixture
            .replacingOccurrences(of: "'", with: "'\\''")
        let path = try writeTempScript("#!/bin/sh\nprintf '\(escaped)'")
        defer { try? FileManager.default.removeItem(atPath: path) }

        let adapter = SubprocessExecCredentialAdapter(allowlist: { _ in true })
        let auth = makeAuth(command: path)
        do {
            _ = try await adapter.resolve(auth: auth)
            XCTFail("Expected ExecPluginError.parseError")
        } catch ExecPluginError.parseError(let detail) {
            XCTAssertTrue(
                detail.contains("token") || detail.contains("clientCertificate"),
                "detail=\(detail)"
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - EnvironmentInjectionTests

/// Validates that environment variables from `ExecPluginAuth.env` are passed
/// into the subprocess and accessible via the command's environment.
final class EnvironmentInjectionTests: XCTestCase {

    func test_envVar_is_injected_and_visible_to_subprocess() async throws {
        // Write a script that reads EXEC_TEST_VAR and echoes JSON containing it.
        let scriptContent = """
        #!/bin/sh
        VALUE="${EXEC_TEST_VAR:-missing}"
        printf '{"apiVersion":"client.authentication.k8s.io/v1","kind":"ExecCredential","status":{"token":"'
        printf '%s' "$VALUE"
        printf '"}}'
        """
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("env_inject_\(UUID().uuidString).sh")
        try scriptContent.write(to: tmp, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: tmp.path
        )
        defer { try? FileManager.default.removeItem(atPath: tmp.path) }

        let adapter = SubprocessExecCredentialAdapter(allowlist: { _ in true })
        let auth = makeAuth(
            command: tmp.path,
            env: [EnvVar(name: "EXEC_TEST_VAR", value: "injected-value-xyz")]
        )
        let resolved = try await adapter.resolve(auth: auth)
        guard case .bearerToken(let bt) = resolved else {
            return XCTFail("Expected .bearerToken, got \(resolved)")
        }
        XCTAssertEqual(bt.token, "injected-value-xyz")
    }
}

// MARK: - ExecCredentialJSONDecoderTests

/// Unit tests for the decoder in isolation — no subprocess involvement.
final class ExecCredentialJSONDecoderTests: XCTestCase {

    func test_decode_bearerToken_fixture() throws {
        let data = Data(bearerTokenFixture.utf8)
        let output = try ExecCredentialJSONDecoder.decode(data)
        guard case .bearerToken(let bt) = output.authInfo else {
            return XCTFail("Expected .bearerToken")
        }
        XCTAssertEqual(bt.token, "test-token-abc123")
    }

    func test_decode_clientCert_fixture() throws {
        let data = Data(clientCertFixture.utf8)
        let output = try ExecCredentialJSONDecoder.decode(data)
        guard case .clientCert(let cc) = output.authInfo else {
            return XCTFail("Expected .clientCert")
        }
        XCTAssertFalse(cc.certPEM.isEmpty)
        XCTAssertFalse(cc.keyPEM.isEmpty)
    }

    func test_decode_garbage_throws_parseError() {
        let data = Data("{{ not json".utf8)
        XCTAssertThrowsError(try ExecCredentialJSONDecoder.decode(data)) { error in
            guard case ExecPluginError.parseError = error else {
                return XCTFail("Expected ExecPluginError.parseError, got \(error)")
            }
        }
    }

    func test_decode_emptyStatus_throws_parseError() {
        let data = Data(emptyStatusFixture.utf8)
        XCTAssertThrowsError(try ExecCredentialJSONDecoder.decode(data)) { error in
            guard case ExecPluginError.parseError = error else {
                return XCTFail("Expected ExecPluginError.parseError, got \(error)")
            }
        }
    }
}
