import XCTest
@testable import ScrivnerCore

final class PageTests: XCTestCase {
    let kathmandu = UTCOffset(string: "+05:45")!
    func at(_ iso: String) -> Instant { Instant(iso: iso)! }

    func testClockStyles() {
        func both(_ iso: String, _ offset: String) -> [String] {
            [Wording.clock(at(iso), offset: UTCOffset(string: offset)!, style: .twentyFourHour),
             Wording.clock(at(iso), offset: UTCOffset(string: offset)!, style: .twelveHour)]
        }
        XCTAssertEqual(both("2026-11-23T04:57:10.120Z", "+05:45"), ["10:42", "10:42 am"])
        XCTAssertEqual(both("2026-11-23T18:20:00.000Z", "+05:45"), ["00:05", "12:05 am"])
        XCTAssertEqual(both("2026-11-23T06:15:00.000Z", "+05:45"), ["12:00", "12:00 pm"])
        XCTAssertEqual(both("2026-11-23T13:00:00.000Z", "-09:30"), ["03:30", "3:30 am"])
        XCTAssertEqual(both("2026-11-23T17:45:59.999Z", "+00:00"), ["17:45", "5:45 pm"])
    }
    func testZones() {
        XCTAssertEqual(Wording.zone(UTCOffset(string: "+05:45")!), "UTC+5:45")
        XCTAssertEqual(Wording.zone(UTCOffset(string: "-09:30")!), "UTC-9:30")
        XCTAssertEqual(Wording.zone(UTCOffset(seconds: 0)), "UTC+0")
        XCTAssertEqual(Wording.zone(UTCOffset(string: "+01:00")!), "UTC+1")
        XCTAssertEqual(Wording.zone(UTCOffset(string: "-11:00")!), "UTC-11")
    }
    func testLengths() {
        XCTAssertEqual(Wording.length(milliseconds: 48_000), "0:48")
        XCTAssertEqual(Wording.length(milliseconds: 727_000), "12:07")
        XCTAssertEqual(Wording.length(milliseconds: 3_723_000), "1:02:03")
        XCTAssertEqual(Wording.length(milliseconds: 999), "0:01")
        XCTAssertEqual(Wording.length(milliseconds: 0), "0:00")
        XCTAssertEqual(Wording.length(milliseconds: -5), "0:00")
    }
    func testMarkerWording() {
        XCTAssertEqual(MarkerType.allCases.map { Wording.marker($0, detail: nil) },
                       ["Recording started", "Paused", "Resumed", "Stopped", "Interrupted", "Location off", "Location on"])
        XCTAssertEqual(Wording.marker(.interrupted, detail: "phone call"), "Interrupted (phone call)")
        XCTAssertEqual(Wording.marker(.interrupted, detail: "crash-recovered"), "Interrupted (the app was closed unexpectedly)")
    }

    func exampleManifest() throws -> Manifest {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("page-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        return try SessionStore.load(try ExampleSession.write(in: root))
    }
    func testThePageOfTheWorkedExample() throws {
        let page = Page(try exampleManifest(), style: .twentyFourHour)
        XCTAssertEqual(page.title, "Market visit")
        XCTAssertEqual(page.rows.map(\.time), ["10:42", "10:43", "10:45", "10:45", "10:49", "10:50", "10:51", "10:51", "10:52", "10:52", "10:53", "10:54", "10:55"])
        XCTAssertEqual(page.rows[0].content, .marker("Recording started · local time, UTC+5:45"))
        XCTAssertEqual(page.rows[1].content, .text("P-014 has run the stall since 2009. Took it over from her aunt, who still does the early shift on Saturdays.", edited: false))
        XCTAssertEqual(page.rows[2].content, .photo(file: "photos/photo-0001.heic"))
        XCTAssertEqual(page.rows[4].content, .video(file: "video/clip-0001.mov", length: "0:48", note: nil))
        XCTAssertEqual(page.rows[6].content, .marker("Paused · local time, UTC+5:45"))
        XCTAssertEqual(page.rows[7].content, .marker("Location off"))
        XCTAssertEqual(page.rows[9].content, .video(file: "video/clip-0002.mov", length: "0:12", note: "no sound"))
        XCTAssertEqual(page.rows[12].content, .marker("Stopped · local time, UTC+5:45"))
        XCTAssertEqual(page.rows.indices.filter { !page.rows[$0].isOnAudio }, [7, 8, 9])
        XCTAssertEqual(Set(page.rows.map(\.id)).count, 13)
        XCTAssertEqual(Page(try exampleManifest(), style: .twelveHour).rows.first?.time, "10:42 am")
    }
    func testEachRowShowsItsOwnLocalTime() throws {
        let start = at("2026-11-23T18:13:10.000Z")
        func moment(_ seconds: Double, _ offset: String) -> Moment {
            Moment(host: 9 + seconds, wall: start.adding(milliseconds: Int64(seconds * 1000)), utcOffset: UTCOffset(string: offset)!, timeZone: "Etc/Test")
        }
        var t = SessionTimeline(title: "Late", participants: [], researcher: nil, device: DeviceInfo(model: "m", os: "o", app: "a"),
                                startLocation: nil, at: moment(0, "+05:45"), ids: SeededIdSource(seed: 4))
        try t.addText("before midnight", at: moment(60, "+05:45"))     // 23:59 local
        try t.addText("after midnight", at: moment(120, "+05:45"))     // 00:00 the next day
        try t.addText("after crossing a border", at: moment(180, "+05:30"))   // 23:46 on the first day again
        let page = Page(t.manifest, style: .twentyFourHour)
        XCTAssertEqual(page.rows.map(\.time), ["23:59", "00:00", "23:46"])
        XCTAssertEqual(page.rows.map(\.isOnAudio), [false, false, false])
    }
    func testEditedAndUnfinishedThings() throws {
        func moment(_ seconds: Double) -> Moment {
            Moment(host: 9 + seconds, wall: at("2026-11-23T04:57:10.120Z").adding(milliseconds: Int64(seconds * 1000)), utcOffset: kathmandu, timeZone: "Asia/Kathmandu")
        }
        var t = SessionTimeline(title: "T", participants: [], researcher: nil, device: DeviceInfo(model: "m", os: "o", app: "a"),
                                startLocation: nil, at: moment(0), ids: SeededIdSource(seed: 4))
        let note = try t.addText("first", at: moment(1))
        try t.editText(id: note, text: "first, corrected", at: moment(50))
        let locked = try t.startClip(file: "video/clip-0001.mov", gps: nil, at: moment(60))
        try t.endClip(id: locked, by: .lock, at: moment(70))
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(80))
        let left = try t.startClip(file: "video/clip-0002.mov", gps: nil, at: moment(90))
        try t.endClip(id: left, by: .background, at: moment(95))
        try t.startClip(file: "video/clip-0003.mov", gps: nil, at: moment(100))
        let rows = Page(t.manifest, style: .twentyFourHour).rows
        XCTAssertEqual(rows[0].content, .text("first, corrected", edited: true))
        XCTAssertEqual(rows[1].content, .video(file: "video/clip-0001.mov", length: "0:10", note: "no sound, ended when the phone locked"))
        XCTAssertEqual(rows[3].content, .video(file: "video/clip-0002.mov", length: "0:05", note: "ended when the app left the screen"))
        XCTAssertEqual(rows[4].content, .video(file: "video/clip-0003.mov", length: nil, note: "still recording"))
    }
    func testNotesUseTheSameWords() throws {
        // notes.md for the worked example is unchanged by sharing its wording with the page.
        let committed = try XCTUnwrap(ExampleSessionTests.committedExample()).appendingPathComponent("notes.md")
        XCTAssertEqual(NotesMarkdown.render(try exampleManifest()), try String(contentsOf: committed, encoding: .utf8))
        // A crash reads the same in notes.md as on the page.
        var m = ManifestCodingTests.sample()
        m.items.append(.marker(Placement(id: "00000000-0000-7000-8000-000000000009", at: m.createdAt, utcOffset: m.utcOffset, spanId: nil, offsetMs: nil),
                               type: .interrupted, detail: "crash-recovered"))
        XCTAssertTrue(NotesMarkdown.render(m).contains("*Interrupted (the app was closed unexpectedly)*"))
        XCTAssertEqual(Page(m, style: .twentyFourHour).rows.last?.content, .marker("Interrupted (the app was closed unexpectedly) · local time, UTC+0"))
    }
}
