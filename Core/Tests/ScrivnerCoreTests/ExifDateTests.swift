import XCTest
@testable import ScrivnerCore

final class ExifDateTests: XCTestCase {
    func testPlainDate() {
        let d = ExifDate("2026:11:23 10:44:02")
        XCTAssertEqual(d?.local.iso, "2026-11-23T10:44:02.000Z")
        XCTAssertNil(d?.offset); XCTAssertNil(d?.instant); XCTAssertEqual(d?.hasFraction, false)
    }
    func testFractionAndOffset() {
        let d = ExifDate("2026:11:23 10:44:02.120+05:45")
        XCTAssertEqual(d?.local.iso, "2026-11-23T10:44:02.120Z")
        XCTAssertEqual(d?.offset?.string, "+05:45")
        XCTAssertEqual(d?.instant?.iso, "2026-11-23T04:59:02.120Z")
        XCTAssertEqual(d?.hasFraction, true)
    }
    func testZuluAndLongFraction() {
        XCTAssertEqual(ExifDate("2026:11:23 10:47:20.120000Z")?.instant?.iso, "2026-11-23T10:47:20.120Z")
        XCTAssertEqual(ExifDate("2026:11:23 10:47:20-09:30")?.instant?.iso, "2026-11-23T20:17:20.000Z")
        XCTAssertEqual(ExifDate("2026:11:23 10:47:20.5")?.local.iso, "2026-11-23T10:47:20.500Z")
        XCTAssertEqual(ExifDate("2026:11:23 10:47:20.012")?.local.iso, "2026-11-23T10:47:20.012Z")
    }
    func testRejects() {
        for bad in ["0000:00:00 00:00:00", "garbage", "2026:02:30 10:00:00", "2026:11:23", "2026:11:23 24:00:00",
                    "2026:11:23 10:44:02+5", "2026:11:23 10:44:02.", "2026:11:23 10:44:02.1234567", "2026:11:23 10:44:02+19:00", ""] {
            XCTAssertNil(ExifDate(bad), bad)
        }
    }
    func testInstantFromFields() {
        XCTAssertEqual(Instant(year: 2024, month: 2, day: 29, hour: 23, minute: 59, second: 59, millisecond: 999)?.iso, "2024-02-29T23:59:59.999Z")
        XCTAssertNil(Instant(year: 2026, month: 2, day: 29, hour: 0, minute: 0, second: 0, millisecond: 0))
        XCTAssertNil(Instant(year: 2026, month: 13, day: 1, hour: 0, minute: 0, second: 0, millisecond: 0))
        XCTAssertNil(Instant(year: 2026, month: 1, day: 1, hour: 0, minute: 60, second: 0, millisecond: 0))
        XCTAssertNil(Instant(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0, millisecond: 1000))
    }
}
