// Tests/AppShellTests/LocaleSanitizerTests.swift
// Tests: LocaleSanitizer — ADR-0039 locale sanitization.

import Testing
import AppShell

// MARK: - LocaleSanitizerTests

@Suite("LocaleSanitizer — ADR-0039")
struct LocaleSanitizerTests {

    // MARK: Accepted inputs

    @Test("Accepts a bare two-letter language code")
    func acceptsBareTwoLetterCode() {
        #expect(LocaleSanitizer.sanitize("en") == "en")
    }

    @Test("Accepts a language-region pair (BCP 47 canonical)")
    func acceptsLanguageRegionPair() {
        #expect(LocaleSanitizer.sanitize("pt-BR") == "pt-BR")
        #expect(LocaleSanitizer.sanitize("es-ES") == "es-ES")
        #expect(LocaleSanitizer.sanitize("zh-CN") == "zh-CN")
    }

    @Test("Accepts a language-script-region triplet")
    func acceptsLanguageScriptRegionTriplet() {
        // zh-Hans-CN: language + script + region
        #expect(LocaleSanitizer.sanitize("zh-Hans-CN") != nil)
    }

    @Test("Accepts underscore-separated POSIX form without encoding suffix")
    func acceptsUnderscoreSeparatedWithoutEncoding() {
        // pt_BR should normalise to pt-BR internally and return the original.
        #expect(LocaleSanitizer.sanitize("pt_BR") == "pt_BR")
    }

    // MARK: Rejected inputs

    @Test("Rejects @calendar= extended identifier")
    func rejectsCalendarExtension() {
        #expect(LocaleSanitizer.sanitize("en@calendar=gregorian") == nil)
    }

    @Test("Rejects POSIX encoding suffix (.UTF-8)")
    func rejectsPosixEncodingSuffix() {
        #expect(LocaleSanitizer.sanitize("en_US.UTF-8") == nil)
    }

    @Test("Rejects @timezone= extended identifier")
    func rejectsTimezoneExtension() {
        #expect(LocaleSanitizer.sanitize("de@timezone=Europe/Berlin") == nil)
    }

    @Test("Rejects @collation= extended identifier")
    func rejectsCollationExtension() {
        #expect(LocaleSanitizer.sanitize("fr@collation=phonebook") == nil)
    }

    @Test("Rejects + BCP 47 extension subtag")
    func rejectsBcp47PlusExtension() {
        #expect(LocaleSanitizer.sanitize("en-US+u-ca-gregory") == nil)
    }

    @Test("Rejects garbage / injection attempt")
    func rejectsGarbage() {
        #expect(LocaleSanitizer.sanitize("'; DROP TABLE locales; --") == nil)
        #expect(LocaleSanitizer.sanitize("") == nil)
        #expect(LocaleSanitizer.sanitize("123") == nil)
    }
}
