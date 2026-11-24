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
    func testNumbersThatCannotBeWritten() {
        var m = base(); m.startLocation = GeoPoint(lat: 38.7, lon: -9.1, alt: .infinity, accuracyM: .nan)
        XCTAssertEqual(paths(m), ["startLocation.alt", "startLocation.accuracyM"])
        m = base(); m.startLocation = GeoPoint(lat: .nan, lon: 0, alt: nil, accuracyM: nil)
        XCTAssertEqual(paths(m), ["startLocation.lat"])
        m = base(); m.utcOffset = UTCOffset(seconds: 100_000)
        XCTAssertEqual(paths(m), ["utcOffset"])
        m = base(); m.spans[0].utcOffset = UTCOffset(seconds: -64_801); m.items[0].placement.utcOffset = UTCOffset(seconds: 64_801)
        XCTAssertEqual(paths(m), ["spans[0].utcOffset", "items[0].utcOffset"])
    }
    func testStrokesArePlacedLikeItems() {
        let at = base().items[0].placement.at
        let span = base().spans[0].id
        func withStroke(_ spanId: String?, _ offsetMs: Int?, _ bounds: [Double] = [0, 0, 1, 1]) -> Manifest {
            var m = base()
            var p = m.items[0].placement; p.id = "00000000-0000-7000-8000-000000000003"
            m.items.append(.ink(p, endAt: nil, file: "ink/ink-0001.png", sha256: nil, data: "ink/ink-0001.drawing", dataSha256: nil,
                                strokes: [InkStroke(at: at, spanId: spanId, offsetMs: offsetMs, bounds: bounds)]))
            return m
        }
        XCTAssertEqual(paths(withStroke(span, 70_000)), [])
        XCTAssertEqual(paths(withStroke(nil, nil)), [])
        XCTAssertEqual(paths(withStroke(nil, 70_000)), ["items[1].strokes[0].spanId"])
        XCTAssertEqual(paths(withStroke(span, nil)), ["items[1].strokes[0].spanId"])
        XCTAssertEqual(paths(withStroke("00000000-0000-7000-8000-00000000000f", 1)), ["items[1].strokes[0].spanId"])
        XCTAssertEqual(paths(withStroke(span, -1)), ["items[1].strokes[0].offsetMs"])
        XCTAssertEqual(paths(withStroke(span, 1, [0, 0, .infinity, 1])), ["items[1].strokes[0].bounds"])
        var closed = withStroke(span, 70_000); closed.spans[0].durationMs = 69_000; closed.spans[0].endedBy = .stop
        XCTAssertEqual(paths(closed), ["items[1].strokes[0].offsetMs"])
    }
    func testFinishedNeedsClosedSpansAndHashes() {
        XCTAssertEqual(paths(base(), finished: true), ["spans[0].endedBy", "spans[0].sha256"])
    }
}
