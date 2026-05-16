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

    // MARK: Catalogue lookup — full F01-F20 coverage (ADR-0041 + ADR-0042)

    @Test("FailureCatalogue contains all 20 entries (F01-F20)")
    func catalogueHasAllEntries() {
        #expect(FailureCatalogue.all.count >= 20)
    }

    @Test("Legacy F01-F12 entries resolve with correct severity")
    func legacyCodesResolve() {
        let expectations: [(code: String, severity: Severity)] = [
            ("F01", .error),    // network unreachable
            ("F02", .error),    // auth expired
            ("F03", .warning),  // watch 410
            ("F04", .warning),  // mutation 409
            ("F05", .critical), // audit chain tamper
            ("F06", .error),    // kubeconfig parse
            ("F07", .warning),  // LLM rate limit
            ("F08", .critical), // prompt injection
            ("F09", .error),    // Helm release failure
            ("F10", .error),    // port-forward bind conflict
            ("F11", .critical), // database migration failure
            ("F12", .error),    // MCP server unavailable
        ]
        for (code, expectedSeverity) in expectations {
            let entry = FailureCatalogue.entry(for: code)
            #expect(entry != nil, "Catalogue missing entry for \(code)")
            #expect(entry?.severity == expectedSeverity,
                    "\(code) expected severity \(expectedSeverity), got \(String(describing: entry?.severity))")
        }
    }

    @Test("New F13-F20 entries resolve with correct severity (ADR-0041 expansion)")
    func newCodesResolve() {
        let expectations: [(code: String, severity: Severity, recovery: RecoveryStrategy)] = [
            ("F13", .warning,  .retry),   // LLM provider rate limit
            ("F14", .error,    .reauth),  // LLM provider auth fail
            ("F15", .warning,  .reload),  // port-forward target gone
            ("F16", .error,    .manual),  // Helm release corrupted
            ("F17", .critical, .manual),  // audit log tamper detected
            ("F18", .critical, .manual),  // disk full
            ("F19", .warning,  .reload),  // event notification dropped
            ("F20", .critical, .manual),  // non-local storage volume (ADR-0042)
        ]
        for (code, expectedSeverity, expectedRecovery) in expectations {
            let entry = FailureCatalogue.entry(for: code)
            #expect(entry != nil, "Catalogue missing entry for \(code)")
            #expect(entry?.severity == expectedSeverity,
                    "\(code) expected severity \(expectedSeverity)")
            #expect(entry?.recovery == expectedRecovery,
                    "\(code) expected recovery \(expectedRecovery)")
        }
    }

    @Test("All catalogue codes match their declared code field")
    func codeFieldConsistency() {
        for entry in FailureCatalogue.all {
            let looked = FailureCatalogue.entry(for: entry.code)
            #expect(looked?.code == entry.code,
                    "Entry \(entry.code) round-trips through catalogue lookup")
        }
    }

    @Test("Unknown code returns nil from catalogue")
    func unknownCodeReturnsNil() {
        #expect(FailureCatalogue.entry(for: "F999") == nil)
    }
}

// MARK: - ErrorMapper tests

@Suite("ErrorMapper — ADR-0041")
struct ErrorMapperTests {

    @Test("URLError.notConnectedToInternet maps to F01")
    func urlErrorMapsToF01() {
        let error = URLError(.notConnectedToInternet)
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F01")
        #expect(entry.severity == .error)
    }

    @Test("URLError.userAuthenticationRequired maps to F02")
    func urlErrorAuthMapsToF02() {
        let error = URLError(.userAuthenticationRequired)
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F02")
    }

    @Test("HTTPStatusError 401 maps to F02")
    func http401MapsToF02() {
        let error = HTTPStatusError(statusCode: 401)
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F02")
    }

    @Test("HTTPStatusError 409 maps to F04")
    func http409MapsToF04() {
        let error = HTTPStatusError(statusCode: 409)
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F04")
    }

    @Test("HTTPStatusError 410 maps to F03")
    func http410MapsToF03() {
        let error = HTTPStatusError(statusCode: 410)
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F03")
    }

    @Test("HTTPStatusError 429 maps to F07")
    func http429MapsToF07() {
        let error = HTTPStatusError(statusCode: 429)
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F07")
    }

    @Test("CocoaError.fileWriteOutOfSpace maps to F18")
    func enospcMapsToF18() {
        let error = CocoaError(.fileWriteOutOfSpace)
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F18")
        #expect(entry.severity == .critical)
    }

    @Test("POSIX ENOSPC maps to F18")
    func posixEnospcMapsToF18() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F18")
    }

    @Test("POSIX ENOLCK maps to F20 (network-volume lock failure)")
    func posixEnolckMapsToF20() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOLCK))
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F20")
    }

    @Test("Unknown error falls back to F01")
    func unknownErrorFallsBackToF01() {
        struct Opaque: Error {}
        let entry = ErrorMapper.entry(for: Opaque())
        #expect(entry.code == "F01")
    }

    @Test("DecodingError maps to F16 (Helm release corrupted)")
    func decodingErrorMapsToF16() {
        let error = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "test"))
        let entry = ErrorMapper.entry(for: error)
        #expect(entry.code == "F16")
    }
}
