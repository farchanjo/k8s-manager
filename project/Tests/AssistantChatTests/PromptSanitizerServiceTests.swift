// PromptSanitizerServiceTests.swift — assistant_chat bounded context
// XCTest coverage: PromptSanitizerService Layer-1 sanitization (ADR-0048).

import XCTest
@testable import AssistantChat

// MARK: - PromptSanitizerServiceTests

final class PromptSanitizerServiceTests: XCTestCase {
    // MARK: - Helpers

    private let sanitizer = PromptSanitizerService()

    // MARK: - Test 1: Clean input passes through unchanged

    func test_sanitize_cleanInput_returnsUnchanged() {
        let input = "Show me all pods in default namespace."
        let result = sanitizer.sanitize(input)

        XCTAssertEqual(result.sanitized, input)
        XCTAssertFalse(result.wasTruncated)
    }

    // MARK: - Test 2: NUL bytes are stripped

    func test_sanitize_nulBytes_areStripped() {
        let input = "normal\u{00}text"
        let result = sanitizer.sanitize(input)

        XCTAssertFalse(result.sanitized.contains("\u{00}"))
        XCTAssertEqual(result.sanitized, "normaltext")
    }

    // MARK: - Test 3: All control characters 0x01-0x08 stripped

    func test_sanitize_controlCharactersBeforeLF_areStripped() {
        // BEL (0x07) and BS (0x08) should be removed.
        let input = "abc\u{07}\u{08}def"
        let result = sanitizer.sanitize(input)

        XCTAssertEqual(result.sanitized, "abcdef")
    }

    // MARK: - Test 4: \n (0x0A) is preserved

    func test_sanitize_lineFeed_isPreserved() {
        let input = "line1\nline2"
        let result = sanitizer.sanitize(input)

        XCTAssertEqual(result.sanitized, "line1\nline2")
    }

    // MARK: - Test 5: \t (0x09) is preserved

    func test_sanitize_tab_isPreserved() {
        let input = "col1\tcol2"
        let result = sanitizer.sanitize(input)

        XCTAssertEqual(result.sanitized, "col1\tcol2")
    }

    // MARK: - Test 6: DEL (0x7F) is stripped

    func test_sanitize_del_isStripped() {
        let input = "text\u{7F}more"
        let result = sanitizer.sanitize(input)

        XCTAssertEqual(result.sanitized, "textmore")
    }

    // MARK: - Test 7: Control chars 0x10-0x1F stripped

    func test_sanitize_highControlChars_areStripped() {
        // DC1 (0x11), DC4 (0x14), ESC (0x1B)
        let input = "data\u{11}value\u{14}end\u{1B}"
        let result = sanitizer.sanitize(input)

        XCTAssertEqual(result.sanitized, "datavalueend")
    }

    // MARK: - Test 8: NFC normalization applied

    func test_sanitize_decomposedUnicode_normalizedToNFC() {
        // U+00E9 (é) can be represented as NFC (single codepoint) or NFD (e + combining acute).
        // Input: NFD form (e + U+0301 combining acute accent).
        let nfd = "caf\u{0065}\u{0301}"  // "café" in NFD
        let nfc = "caf\u{00E9}"           // "café" in NFC

        let result = sanitizer.sanitize(nfd)

        XCTAssertEqual(result.sanitized, nfc)
    }

    // MARK: - Test 9: No truncation when input is exactly maxLength

    func test_sanitize_exactlyMaxLength_noTruncation() {
        let shortSanitizer = PromptSanitizerService(maxLength: 10)
        let input = String(repeating: "a", count: 10)
        let result = shortSanitizer.sanitize(input)

        XCTAssertFalse(result.wasTruncated)
        XCTAssertEqual(result.sanitized.count, 10)
    }

    // MARK: - Test 10: Truncation at maxLength + 1

    func test_sanitize_exceedsMaxLength_isTruncated() {
        let shortSanitizer = PromptSanitizerService(maxLength: 10)
        let input = String(repeating: "x", count: 20)
        let result = shortSanitizer.sanitize(input)

        XCTAssertTrue(result.wasTruncated)
        XCTAssertEqual(result.originalLength, 20)
    }

    // MARK: - Test 11: Truncation marker is appended

    func test_sanitize_truncated_markerContainsOriginalLength() {
        let shortSanitizer = PromptSanitizerService(maxLength: 5)
        let input = String(repeating: "z", count: 100)
        let result = shortSanitizer.sanitize(input)

        XCTAssertTrue(result.sanitized.contains("[truncated — original length: 100 chars]"))
    }

    // MARK: - Test 12: Empty string produces empty result without truncation

    func test_sanitize_emptyInput_returnsEmpty() {
        let result = sanitizer.sanitize("")

        XCTAssertEqual(result.sanitized, "")
        XCTAssertFalse(result.wasTruncated)
    }

    // MARK: - Test 13: Mixed control chars and newlines

    func test_sanitize_mixedControlAndNewline_onlyNewlinePreserved() {
        let input = "line1\n\u{03}bad\u{1F}line2\n"
        let result = sanitizer.sanitize(input)

        XCTAssertEqual(result.sanitized, "line1\nbadline2\n")
    }

    // MARK: - Test 14: Default maxLength is 4096

    func test_sanitize_defaultMaxLength_is4096() {
        let defaultSanitizer = PromptSanitizerService()
        let input = String(repeating: "a", count: 4096)
        let result = defaultSanitizer.sanitize(input)

        XCTAssertFalse(result.wasTruncated)

        let overLimit = String(repeating: "a", count: 4097)
        let overResult = defaultSanitizer.sanitize(overLimit)
        XCTAssertTrue(overResult.wasTruncated)
    }
}
