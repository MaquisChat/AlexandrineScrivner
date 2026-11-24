import XCTest
@testable import ScrivnerCore

final class IdsTests: XCTestCase {
    func testLayout() {
        let id = UUIDv7.make(at: Instant(millisecondsSince1970: 0x0123_4567_89AB), randomA: 0xCDE, randomB: 0x0123_4567_89AB_CDEF)
        XCTAssertEqual(id, "01234567-89ab-7cde-8123-456789abcdef")
        XCTAssertTrue(UUIDv7.isValid(id))
        XCTAssertEqual(UUIDv7.shortId(id), "cdef")
    }
    func testExtraRandomBitsAreMasked() {
        let id = UUIDv7.make(at: Instant(millisecondsSince1970: 1), randomA: 0xFFFF, randomB: .max)
        XCTAssertEqual(id, "00000000-0001-7fff-bfff-ffffffffffff")
    }
    func testIsValidRejects() {
        for bad in ["01234567-89AB-7CDE-8123-456789ABCDEF", "01234567-89ab-4cde-8123-456789abcdef",
                    "01234567-89ab-7cde-0123-456789abcdef", "0123456789ab7cde8123456789abcdef", ""] {
            XCTAssertFalse(UUIDv7.isValid(bad), bad)
        }
    }
    func testSeededSourceRepeatsAndRandomSourceIsValid() {
        var a = SeededIdSource(seed: 1), b = SeededIdSource(seed: 1), r = RandomIdSource()
        let t = Instant(millisecondsSince1970: 1_795_430_530_120)
        let first = a.next(at: t)
        XCTAssertEqual(first, b.next(at: t))
        XCTAssertNotEqual(first, a.next(at: t))
        XCTAssertTrue(UUIDv7.isValid(first))
        XCTAssertTrue(UUIDv7.isValid(r.next(at: t)))
    }
}
