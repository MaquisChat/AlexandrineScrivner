import XCTest
@testable import ScrivnerCore

final class ManifestProblemsTests: XCTestCase {
    func base() -> Manifest { ManifestCodingTests.sample() }
    func paths(_ m: Manifest, finished: Bool = false) -> [String] { m.problems(finished: finished).map(\.path) }

    func testConsistentManifestHasNoProblems() { XCTAssertEqual(paths(base()), []) }
    func testIds() {
        var m = base(); m.items[0].placement.id = m.spans[0].id
        XCTAssertEqual(paths(m), ["items[0].id"])
        m = base(); m.spans[0].id = "not-an-id"; m.items[0].placement.spanId = "not-an-id"
        XCTAssertEqual(paths(m), ["spans[0].id"])
    }
    func testPaths() {
        for bad in ["/abs/a.m4a", "audio\\a.m4a", "audio/../a.m4a", "audio//a.m4a", ".hidden/a.m4a", "audio/.a.m4a", ""] {
            var m = base(); m.spans[0].file = bad
            XCTAssertEqual(paths(m), ["spans[0].file"], bad)
        }
        var m = base()
        m.items.append(.photo(m.items[0].placement, file: "audio/audio-001.m4a", sha256: nil, gps: nil))
        m.items[1].placement.id = "00000000-0000-7000-8000-000000000003"
        XCTAssertEqual(paths(m), ["items[1].file"])
    }
    func testPlacement() {
        var m = base(); m.items[0].placement.offsetMs = nil
        XCTAssertEqual(paths(m), ["items[0].spanId"])
        m = base(); m.items[0].placement.spanId = "00000000-0000-7000-8000-00000000000f"
        XCTAssertEqual(paths(m), ["items[0].spanId"])
        m = base(); m.items[0].placement.offsetMs = -1
        XCTAssertEqual(paths(m), ["items[0].offsetMs"])
        m = base(); m.spans[0].durationMs = 60_000; m.spans[0].endedBy = .stop
        XCTAssertEqual(paths(m), ["items[0].offsetMs"])
    }
    func testSpans() {
        var m = base(); m.spans[0].durationMs = 600_000
        XCTAssertEqual(paths(m), ["spans[0].endedBy"])
        m = base(); m.spans.append(m.spans[0]); m.spans[1].id = "00000000-0000-7000-8000-000000000004"; m.spans[1].file = "audio/audio-002.m4a"
        XCTAssertEqual(paths(m), ["spans[0].endedBy"])
    }
    func testHashesAndCoordinates() {
        var m = base(); m.spans[0].sha256 = "ABC"
        XCTAssertEqual(paths(m), ["spans[0].sha256"])
        m = base(); m.startLocation = GeoPoint(lat: 91, lon: 181, alt: nil, accuracyM: nil)
        XCTAssertEqual(paths(m), ["startLocation.lat", "startLocation.lon"])
    }
    func testFinishedNeedsClosedSpansAndHashes() {
        XCTAssertEqual(paths(base(), finished: true), ["spans[0].endedBy", "spans[0].sha256"])
    }
}
