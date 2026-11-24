import XCTest
@testable import ScrivnerCore

final class NamingTests: XCTestCase {
    let at = Instant(iso: "2026-11-23T10:42:10.120Z")!
    let id = "01234567-89ab-7cde-8123-456789abcdef"

    func testSanitizeReplacesForbiddenCharacters() {
        XCTAssertEqual(Naming.sanitize("a<b>c:d\"e/f\\g|h?i*j"), "a-b-c-d-e-f-g-h-i-j")
        XCTAssertEqual(Naming.sanitize("bell\u{07}tab\there"), "bell-tab-here")
    }
    func testSanitizeTidiesSpacesAndDots() {
        XCTAssertEqual(Naming.sanitize("  many   spaces  "), "many spaces")
        XCTAssertEqual(Naming.sanitize("name... "), "name")
        XCTAssertEqual(Naming.sanitize("...hidden"), "hidden")
        XCTAssertEqual(Naming.sanitize(" . . "), "")
    }
    func testSanitizeHandlesReservedNamesAndNFC() {
        XCTAssertEqual(Naming.sanitize("CON"), "_CON")
        XCTAssertEqual(Naming.sanitize("com1.txt"), "_com1.txt")
        XCTAssertEqual(Naming.sanitize("Console"), "Console")
        XCTAssertEqual(Naming.sanitize("e\u{301}").unicodeScalars.count, 1)
        XCTAssertEqual(Naming.sanitize("Рынок 市場 سوق"), "Рынок 市場 سوق")
    }
    func testFolderName() {
        XCTAssertEqual(Naming.sessionFolderName(createdAt: at, utcOffset: UTCOffset(seconds: 0), title: "Market visit", sessionId: id),
                       "2026-11-23 1042 Market visit [cdef]")
        XCTAssertEqual(Naming.sessionFolderName(createdAt: at, utcOffset: UTCOffset(seconds: -5 * 3600), title: "A/B", sessionId: id),
                       "2026-11-23 0542 A-B [cdef]")
        XCTAssertEqual(Naming.sessionFolderName(createdAt: at, utcOffset: UTCOffset(seconds: 0), title: " .. ", sessionId: id),
                       "2026-11-23 1042 [cdef]")
    }
    func testLongTitlesAreCutOnAWholeCharacter() {
        let long = String(repeating: "é👩‍👩‍👧", count: 60)
        let name = Naming.sessionFolderName(createdAt: at, utcOffset: UTCOffset(seconds: 0), title: long, sessionId: id)
        XCTAssertLessThanOrEqual(name.utf8.count, 150)
        XCTAssertTrue(name.hasPrefix("2026-11-23 1042 é👩‍👩‍👧"))
        XCTAssertTrue(name.hasSuffix("… [cdef]"))
        XCTAssertFalse(name.contains("\u{FFFD}"))
    }
}
