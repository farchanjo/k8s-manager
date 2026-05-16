// SharedIdsTests.swift — ProviderProfileId + EditorSessionId typed wrapper coverage
// Target: SharedKernelTests
// Spec: docs/arch/contexts/_shared/schemas/shared_kernel.cue

import XCTest
@testable import SharedKernel

final class SharedIdsTests: XCTestCase {

    // MARK: - ProviderProfileId

    /// ProviderProfileId constructed from rawValue exposes the same string back.
    func test_providerProfileId_rawValueRoundTrip() {
        let raw = "01900000-0000-7000-8000-000000000010"
        let id = ProviderProfileId(rawValue: raw)
        XCTAssertEqual(id.rawValue, raw)
    }

    /// ProviderProfileId convenience initialiser produces the same result as rawValue init.
    func test_providerProfileId_convenienceInit() {
        let raw = "01900000-0000-7000-8000-000000000011"
        let byConvenience = ProviderProfileId(raw)
        let byRaw = ProviderProfileId(rawValue: raw)
        XCTAssertEqual(byConvenience, byRaw)
    }

    /// ProviderProfileId round-trips through Codable without data loss.
    func test_providerProfileId_codableRoundTrip() throws {
        let original = ProviderProfileId("01900000-0000-7000-8000-000000000012")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProviderProfileId.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - EditorSessionId

    /// EditorSessionId constructed from rawValue exposes the same string back.
    func test_editorSessionId_rawValueRoundTrip() {
        let raw = "01900000-0000-7000-8000-000000000020"
        let id = EditorSessionId(rawValue: raw)
        XCTAssertEqual(id.rawValue, raw)
    }

    /// EditorSessionId convenience initialiser produces the same result as rawValue init.
    func test_editorSessionId_convenienceInit() {
        let raw = "01900000-0000-7000-8000-000000000021"
        let byConvenience = EditorSessionId(raw)
        let byRaw = EditorSessionId(rawValue: raw)
        XCTAssertEqual(byConvenience, byRaw)
    }

    /// EditorSessionId round-trips through Codable without data loss.
    func test_editorSessionId_codableRoundTrip() throws {
        let original = EditorSessionId("01900000-0000-7000-8000-000000000022")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EditorSessionId.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    /// ProviderProfileId and EditorSessionId are distinct types; their backing values
    /// cannot be accidentally interchanged.
    func test_typedWrappers_areDistinctTypes() {
        let raw = "01900000-0000-7000-8000-000000000099"
        let profileId = ProviderProfileId(raw)
        let sessionId = EditorSessionId(raw)
        // Equality between the two types is intentionally not defined;
        // verify rawValues match the input string independently.
        XCTAssertEqual(profileId.rawValue, raw)
        XCTAssertEqual(sessionId.rawValue, raw)
    }
}
