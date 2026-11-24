import XCTest
@testable import ScrivnerCore

final class InstantTests: XCTestCase {
    func testIsoRoundTripWithMilliseconds() {
        let i = Instant(iso: "2026-11-23T10:42:10.120Z")!
        XCTAssertEqual(i.millisecondsSince1970, 1_795_430_530_120)
        XCTAssertEqual(i.iso, "2026-11-23T10:42:10.120Z")
    }
    func testIsoRejectsOtherShapes() {
        for bad in ["2026-11-23T10:42:10Z", "2026-11-23T10:42:10.120+00:00", "2026-11-23 10:42:10.120Z",
                    "2026-13-01T00:00:00.000Z", "2026-02-30T00:00:00.000Z", ""] {
            XCTAssertNil(Instant(iso: bad), bad)
        }
    }
    func testEpochAndLeapDay() {
        XCTAssertEqual(Instant(millisecondsSince1970: 0).iso, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(Instant(iso: "2028-02-29T23:59:59.999Z")!.adding(milliseconds: 1).iso, "2028-03-01T00:00:00.000Z")
    }
    func testDateIsRoundedToMilliseconds() {
        XCTAssertEqual(Instant(date: Date(timeIntervalSince1970: 1.2346)).millisecondsSince1970, 1235)
    }
    func testOffsetStrings() {
        XCTAssertEqual(UTCOffset(seconds: 0).string, "+00:00")
        XCTAssertEqual(UTCOffset(seconds: -19_800).string, "-05:30")
        XCTAssertEqual(UTCOffset(string: "+05:45")?.seconds, 20_700)
        for bad in ["Z", "+5:45", "+05:60", "05:45", "+25:00"] { XCTAssertNil(UTCOffset(string: bad), bad) }
    }
    func testLocalClockAppliesTheOffset() {
        let c = LocalClock(Instant(iso: "2026-11-23T23:30:00.000Z")!, offset: UTCOffset(seconds: 3600))
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 11, 24, 0, 30, 0])
    }
}
