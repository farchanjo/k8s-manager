// Tests/SharedKernelTests/FailureModeTests.swift
// Tests: FailureMode + FailureCatalogue — ADR-0041.

import Testing
import Foundation
import SharedKernel

@Suite("FailureMode + FailureCatalogue — ADR-0041")
struct FailureModeTests {

    // MARK: Codable round-trip

    @Test("FailureMode encodes and decodes without loss")
    func codableRoundTrip() throws {
        let mode = FailureMode(
            code: "F99",
            title: "Test Mode",
            userMessage: "This is a test failure.",
            recovery: .retry,
            severity: .warning
        )
        let data = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(FailureMode.self, from: data)
        #expect(decoded == mode)
    }

    @Test("RecoveryStrategy raw values survive Codable round-trip")
    func recoveryStrategyCodable() throws {
        for strategy in RecoveryStrategy.allCases {
            let data = try JSONEncoder().encode(strategy)
            let decoded = try JSONDecoder().decode(RecoveryStrategy.self, from: data)
            #expect(decoded == strategy)
        }
    }

    // MARK: Catalogue lookup

    @Test("FailureCatalogue contains at least 8 entries")
    func catalogueHasMinimumEntries() {
        #expect(FailureCatalogue.all.count >= 8)
    }

    @Test("Known failure codes resolve to correct titles")
    func knownCodesResolve() {
        let expectations: [(code: String, severity: Severity)] = [
            ("F01", .error),    // network unreachable
            ("F02", .error),    // auth expired
            ("F03", .warning),  // watch 410
            ("F04", .warning),  // mutation 409
            ("F05", .critical), // audit chain tamper
            ("F06", .error),    // kubeconfig parse
            ("F07", .warning),  // LLM rate limit
            ("F08", .critical), // prompt injection
        ]
        for (code, expectedSeverity) in expectations {
            let entry = FailureCatalogue.entry(for: code)
            #expect(entry != nil, "Catalogue missing entry for \(code)")
            #expect(entry?.severity == expectedSeverity,
                    "\(code) expected severity \(expectedSeverity), got \(String(describing: entry?.severity))")
        }
    }

    @Test("Unknown code returns nil from catalogue")
    func unknownCodeReturnsNil() {
        #expect(FailureCatalogue.entry(for: "F999") == nil)
    }
}
