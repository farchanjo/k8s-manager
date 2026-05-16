// Tests/AppShellTests/Config/SecretRevealTests.swift
// Coverage: DockerConfigJSONParser parse + mask logic, SecretRevealSheetViewModel state.
// ADR ref: ADR-0063 §Confirmation

import XCTest
import Dependencies
@testable import AppShell
import LocalPersistence
import SharedKernel

// MARK: - DockerConfigJSONParserTests

final class DockerConfigJSONParserTests: XCTestCase {

    // MARK: Standard auths format

    func test_parse_standard_auths_extractsUsernameAndPassword() throws {
        let json = """
        {
          "auths": {
            "registry.io": {
              "username": "alice",
              "password": "s3cr3t"
            }
          }
        }
        """
        let base64 = Data(json.utf8).base64EncodedString()
        let config = try DockerConfigJSONParser.parse(base64)

        XCTAssertEqual(config.registries.count, 1)
        let reg = try XCTUnwrap(config.registries.first)
        XCTAssertEqual(reg.registry, "registry.io")
        XCTAssertEqual(reg.username, "alice")
        XCTAssertEqual(reg.password, "s3cr3t")
    }

    // MARK: Legacy auth base64 field

    func test_parse_legacyAuthField_decodesUserAndPassword() throws {
        // "bob:hunter2" encoded as base64
        let authField = Data("bob:hunter2".utf8).base64EncodedString()
        let json = """
        {
          "auths": {
            "ghcr.io": {
              "auth": "\(authField)"
            }
          }
        }
        """
        let base64 = Data(json.utf8).base64EncodedString()
        let config = try DockerConfigJSONParser.parse(base64)

        XCTAssertEqual(config.registries.count, 1)
        let reg = try XCTUnwrap(config.registries.first)
        XCTAssertEqual(reg.registry, "ghcr.io")
        XCTAssertEqual(reg.username, "bob")
        XCTAssertEqual(reg.password, "hunter2")
    }

    // MARK: Multiple registries sorted

    func test_parse_multipleRegistries_sortedByHostname() throws {
        let json = """
        {
          "auths": {
            "zoo.io": { "username": "z", "password": "zp" },
            "alpha.io": { "username": "a", "password": "ap" }
          }
        }
        """
        let base64 = Data(json.utf8).base64EncodedString()
        let config = try DockerConfigJSONParser.parse(base64)

        XCTAssertEqual(config.registries.count, 2)
        XCTAssertEqual(config.registries[0].registry, "alpha.io")
        XCTAssertEqual(config.registries[1].registry, "zoo.io")
    }

    // MARK: Malformed JSON returns ParseError

    func test_parse_malformedJSON_throwsInvalidJSON() {
        let invalidBase64 = Data("not json {{{".utf8).base64EncodedString()
        XCTAssertThrowsError(try DockerConfigJSONParser.parse(invalidBase64)) { error in
            guard case DockerConfigParseError.invalidJSON = error else {
                XCTFail("Expected .invalidJSON, got \(error)")
                return
            }
        }
    }

    // MARK: Missing auths map returns ParseError

    func test_parse_missingAuthsMap_throwsMissingAuthsMap() {
        let json = """
        { "credsStore": "osxkeychain" }
        """
        let base64 = Data(json.utf8).base64EncodedString()
        XCTAssertThrowsError(try DockerConfigJSONParser.parse(base64)) { error in
            guard case DockerConfigParseError.missingAuthsMap = error else {
                XCTFail("Expected .missingAuthsMap, got \(error)")
                return
            }
        }
    }

    // MARK: Empty credentials produce nil fields

    func test_parse_emptyUsernameAndPassword_returnNilFields() throws {
        let json = """
        {
          "auths": {
            "internal.io": { "username": "", "password": "" }
          }
        }
        """
        let base64 = Data(json.utf8).base64EncodedString()
        let config = try DockerConfigJSONParser.parse(base64)

        let reg = try XCTUnwrap(config.registries.first)
        XCTAssertNil(reg.username)
        XCTAssertNil(reg.password)
    }
}

// MARK: - SecretRevealSheetViewModelTests

@MainActor
final class SecretRevealSheetViewModelTests: XCTestCase {

    private let clusterId = ClusterId("test-cluster")

    private func makeRow(type: String = "Opaque") -> SecretRow {
        SecretRow(
            id: UUID(),
            name: "my-secret",
            namespace: "default",
            type: type,
            dataCount: 2,
            age: "1h",
            listItem: makeFakeListItem()
        )
    }

    // MARK: Initial state — all keys masked

    func test_seedKeys_allStartMasked() {
        let sut = SecretRevealSheetViewModel(row: makeRow(), clusterId: clusterId)
        sut.seedKeys(["password", "token"])

        XCTAssertEqual(sut.keyStates["password"], .masked)
        XCTAssertEqual(sut.keyStates["token"], .masked)
        XCTAssertFalse(sut.keyStates["password"]!.isRevealed)
    }

    // MARK: Reveal transitions key to revealed

    func test_reveal_transitionsKeyToRevealed_othersRemainMasked() async {
        await withDependencies {
            $0.secretRevealAudit = NoOpSecretRevealAudit()
        } operation: {
            let sut = SecretRevealSheetViewModel(row: makeRow(), clusterId: clusterId)
            sut.seedKeys(["password", "token"])

            await sut.reveal(key: "password")

            XCTAssertTrue(sut.keyStates["password"]!.isRevealed)
            XCTAssertEqual(sut.keyStates["token"], .masked)
        }
    }

    // MARK: Hide re-masks a revealed key

    func test_hide_remasksRevealedKey() async {
        await withDependencies {
            $0.secretRevealAudit = NoOpSecretRevealAudit()
        } operation: {
            let sut = SecretRevealSheetViewModel(row: makeRow(), clusterId: clusterId)
            sut.seedKeys(["apikey"])
            await sut.reveal(key: "apikey")
            XCTAssertTrue(sut.keyStates["apikey"]!.isRevealed)

            await sut.hide(key: "apikey")

            XCTAssertEqual(sut.keyStates["apikey"], .masked)
        }
    }

    // MARK: orderedKeys is sorted

    func test_orderedKeys_isSortedAlphabetically() {
        let sut = SecretRevealSheetViewModel(row: makeRow(), clusterId: clusterId)
        sut.seedKeys(["zzz", "aaa", "mmm"])

        XCTAssertEqual(sut.orderedKeys, ["aaa", "mmm", "zzz"])
    }

    // MARK: Docker password reveal/hide

    func test_revealDockerPassword_insertsRegistryToRevealedSet() async {
        await withDependencies {
            $0.secretRevealAudit = NoOpSecretRevealAudit()
        } operation: {
            let sut = SecretRevealSheetViewModel(
                row: makeRow(type: "kubernetes.io/dockerconfigjson"),
                clusterId: clusterId
            )
            await sut.revealDockerPassword(registry: "ghcr.io")

            XCTAssertTrue(sut.revealedDockerPasswords.contains("ghcr.io"))
        }
    }

    func test_hideDockerPassword_removesRegistryFromRevealedSet() async {
        await withDependencies {
            $0.secretRevealAudit = NoOpSecretRevealAudit()
        } operation: {
            let sut = SecretRevealSheetViewModel(
                row: makeRow(type: "kubernetes.io/dockerconfigjson"),
                clusterId: clusterId
            )
            await sut.revealDockerPassword(registry: "ghcr.io")
            await sut.hideDockerPassword(registry: "ghcr.io")

            XCTAssertFalse(sut.revealedDockerPasswords.contains("ghcr.io"))
        }
    }

    // MARK: Helpers

    private func makeFakeListItem() -> ResourceListItem {
        ResourceListItem(
            id: UUID(),
            gvk: .core("Secret"),
            namespace: "default",
            name: "my-secret",
            uid: UUID().uuidString,
            creationTimestamp: "2026-01-01T00:00:00Z",
            status: "Active",
            ageSeconds: 3600
        )
    }
}

// MARK: - NoOpSecretRevealAudit (test double)

private struct NoOpSecretRevealAudit: SecretRevealAuditPort, @unchecked Sendable {
    func append(entry: SecretRevealEntry) async throws -> UUID {
        return entry.id
    }
}
