import XCTest
@testable import ScrivnerCore

final class JSONValueTests: XCTestCase {
    func testWrittenFormIsExact() {
        let v = JSONValue.object([
            ("format", .string("ao-field-session")), ("version", .int(1)),
            ("participants", .array([.string("P-014")])), ("empty", .array([])),
            ("gps", .object([("lat", .double(38.7223)), ("alt", .double(12))])),
            ("items", .array([.object([("sound", .bool(true)), ("note", .null)])])),
            ("bounds", .array([.double(0), .double(10.5)])),
        ])
        XCTAssertEqual(v.written(), """
        {
          "format": "ao-field-session",
          "version": 1,
          "participants": ["P-014"],
          "empty": [],
          "gps": {
            "lat": 38.7223,
            "alt": 12.0
          },
          "items": [
            {
              "sound": true,
              "note": null
            }
          ],
          "bounds": [0.0, 10.5]
        }

        """)
    }
    func testStringsAreEscaped() {
        let v = JSONValue.object([("t", .string("say \"hi\" \\ \n\t\u{01} Рынок 市場 👩‍👩‍👧"))])
        XCTAssertEqual(v.written(), "{\n  \"t\": \"say \\\"hi\\\" \\\\ \\n\\t\\u0001 Рынок 市場 👩‍👩‍👧\"\n}\n")
    }
    func testParseRoundTripKeepsOrderAndNumberKinds() throws {
        let text = "{\"b\": 1, \"a\": 1.5, \"c\": [true, null, \"x\"], \"d\": {\"z\": -3}}"
        let v = try JSONValue.parse(text)
        XCTAssertEqual(v, .object([("b", .int(1)), ("a", .double(1.5)),
                                   ("c", .array([.bool(true), .null, .string("x")])), ("d", .object([("z", .int(-3))]))]))
        XCTAssertEqual(try JSONValue.parse(v.written()), v)
        XCTAssertEqual(v["a"], .double(1.5))
        XCTAssertNil(v["missing"])
    }
    func testParseHandlesEscapesAndRejectsRubbish() throws {
        XCTAssertEqual(try JSONValue.parse("\"a\\u00e9\\n\\ud83d\\ude00\""), .string("aé\n😀"))
        for bad in ["", "{", "[1,]", "{\"a\":1,}", "{\"a\" 1}", "01", "1 2", "{\"a\":1,\"a\":2}", "nul", "\"\u{01}\""] {
            XCTAssertThrowsError(try JSONValue.parse(bad), bad)
        }
    }
    func testNumbersTooLargeToHoldAreRefused() {
        XCTAssertThrowsError(try JSONValue.parse("1e400"))
        XCTAssertThrowsError(try JSONValue.parse("[-1e400]"))
        XCTAssertNoThrow(try JSONValue.parse("[1e308, -1e308, 5e-324]"))
    }
}
