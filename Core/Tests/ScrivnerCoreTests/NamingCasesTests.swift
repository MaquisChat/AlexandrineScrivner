import XCTest
@testable import ScrivnerCore

/// Writes `format/naming-cases.json`: awkward session titles and the folder names they give.
/// The workbench check (`tools/workbench-check.sh`) runs the workbench's own name cleaning over
/// each folder name and expects it to come back unchanged, so the workbench would never rename
/// a folder the recorder made.
final class NamingCasesTests: XCTestCase {
    static let titles: [String] = [
        "Market visit",
        "Interview: P-014 / second visit?",
        "  spaces   and\ttabs\nnewlines  ",
        "trailing dots...",
        "CON",
        "com1.txt",
        "Cafe\u{301} de\u{301}ja\u{300} vu",
        "日本語のタイトル 🎙️ 録音",
        "\u{202E}reversed\u{202C} title",
        "zero\u{FEFF}width",
        "nbsp\u{A0}\u{A0}here",
        "del\u{7F}and\u{85}c1",
        "a<b>c|d*e\"f\\g",
        "",
        "...",
        String(repeating: "long title ", count: 40),
        String(repeating: "👩‍👩‍👧‍👦", count: 30),
        String(repeating: "é", count: 200),
    ]

    func testNamingCasesMatchTheCommittedFile() throws {
        let createdAt = Instant(iso: "2026-11-23T04:57:10.120Z")!
        let offset = UTCOffset(string: "+05:45")!
        let cases = Self.titles.map { title -> JSONValue in
            let folder = Naming.sessionFolderName(createdAt: createdAt, utcOffset: offset, title: title,
                                                  sessionId: "01a206c3-e0e8-709d-832a-5cd27a6b13a1")
            XCTAssertLessThanOrEqual(folder.utf8.count, Naming.maxBytes, title)
            XCTAssertTrue(folder.hasPrefix("2026-11-23 1042"), title)
            XCTAssertTrue(folder.hasSuffix(" [13a1]"), title)
            return .object([("title", .string(title)), ("folder", .string(folder))])
        }
        let text = JSONValue.array(cases).written()

        let url = SchemaSamplesTests.format.appendingPathComponent("naming-cases.json")
        if ProcessInfo.processInfo.environment["UPDATE_EXAMPLE"] == "1" {
            try Data(text.utf8).write(to: url)
        }
        XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), text,
                       "format/naming-cases.json is out of date: run the tests once with UPDATE_EXAMPLE=1")
    }
}
