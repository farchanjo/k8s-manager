// Tests/HelmManagementTests/ReleaseDecoderPortTests.swift — helm_management
// ADR ref: ADR-0015 §Phase 1 §Secret decoding

import XCTest
import Dependencies
import SharedKernel
@testable import HelmManagement

// MARK: - ReleaseDecoderPortTests

final class ReleaseDecoderPortTests: XCTestCase {

    // MARK: - Unimplemented default throws .unimplemented

    func test_unimplementedDefaultThrowsUnimplemented() {
        let port = UnimplementedReleaseDecoderPort()
        XCTAssertThrowsError(try port.decode(secretData: Data())) { error in
            guard case ReleaseDecoderError.unimplemented = error else {
                return XCTFail("Expected ReleaseDecoderError.unimplemented, got \(error)")
            }
        }
    }

    // MARK: - Dependency override pattern — live adapter replaces sentinel

    func test_dependencyOverridePatternAllowsInjectingTestDecoder() throws {
        let expectedRelease = makeRelease()
        let stub = StubReleaseDecoderPort(result: expectedRelease)

        let decoded = try withDependencies {
            $0.releaseDecoder = stub
        } operation: {
            @Dependency(\.releaseDecoder) var decoder
            return try decoder.decode(secretData: Data([0x1f, 0x8b]))
        }

        XCTAssertEqual(decoded.id, expectedRelease.id)
        XCTAssertEqual(decoded.name, expectedRelease.name)
        XCTAssertEqual(decoded.namespace, expectedRelease.namespace)
        XCTAssertEqual(decoded.version, expectedRelease.version)
    }
}

// MARK: - Helpers

private func makeRelease() -> Release {
    Release(
        id: UUID(),
        kubernetesContextId: UUID(),
        name: "test-release",
        namespace: "default",
        version: 1,
        status: .deployed,
        chart: ChartMetadata(
            name: "test-chart",
            version: "0.1.0",
            appVersion: nil,
            apiVersion: .v2,
            description: nil,
            type: nil,
            icon: nil,
            dependencies: [],
            maintainers: [],
            home: nil,
            sources: []
        ),
        info: ReleaseInfo(
            firstDeployed: "2024-01-01T00:00:00Z",
            lastDeployed: "2024-01-01T00:00:00Z",
            deleted: nil,
            description: "Install complete",
            status: .deployed,
            notes: ""
        ),
        manifestYAML: "apiVersion: v1\nkind: ConfigMap\n",
        valuesJSON: "{}",
        hooks: [],
        modifiedAtRFC3339: "2024-01-01T00:00:00Z",
        sourceSecretName: "sh.helm.release.v1.test-release.v1"
    )
}

private struct StubReleaseDecoderPort: ReleaseDecoderPort {
    let result: Release

    func decode(secretData: Data) throws -> Release {
        result
    }
}
