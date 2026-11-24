import XCTest
@testable import ScrivnerCore

final class NoteWriterTests: XCTestCase {
    let t0 = Instant(iso: "2026-11-23T04:57:10.120Z")!
    func moment(_ seconds: Double) -> Moment {
        Moment(host: 100 + seconds, wall: t0.adding(milliseconds: Int64(seconds * 1000)),
               utcOffset: UTCOffset(string: "+05:45")!, timeZone: "Asia/Kathmandu")
    }
    func recording() throws -> SessionTimeline {
        var t = SessionTimeline(title: "T", participants: [], researcher: nil, device: DeviceInfo(model: "m", os: "o", app: "a"),
                                startLocation: nil, at: moment(0), ids: SeededIdSource(seed: 6))
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        return t
    }
    /// The notes on the page: text, time, place on the audio, and when last changed.
    func notes(_ t: SessionTimeline) -> [String] {
        t.manifest.items.compactMap { item -> String? in
            guard case .text(let p, let text, let modified) = item else { return nil }
            let seconds = (p.at.millisecondsSince1970 - t0.millisecondsSince1970) / 1000
            let changed = modified.map { " changed@\(($0.millisecondsSince1970 - t0.millisecondsSince1970) / 1000)" } ?? ""
            return "\(text)|at@\(seconds)|offset@\(p.offsetMs.map { String($0 / 1000) } ?? "none")\(changed)"
        }
    }

    func testANoteKeepsTheTimeOfItsFirstCharacter() throws {
        var t = try recording()
        var writer = NoteWriter()
        try writer.typing("P", at: moment(65), in: &t)
        XCTAssertNotNil(writer.openNoteId)
        try writer.typing("P-014 has run the stall since 2009.", at: moment(70), in: &t)
        try writer.finish(in: &t)
        XCTAssertNil(writer.openNoteId)
        XCTAssertEqual(notes(t), ["P-014 has run the stall since 2009.|at@65|offset@65"])
    }
    func testANewParagraphStartsANewNote() throws {
        var t = try recording()
        var writer = NoteWriter()
        try writer.typing("first", at: moment(10), in: &t)
        let first = writer.openNoteId
        try writer.finish(in: &t)
        try writer.typing("second", at: moment(90), in: &t)
        XCTAssertNotEqual(writer.openNoteId, first)
        try writer.finish(in: &t)
        XCTAssertEqual(notes(t), ["first|at@10|offset@10", "second|at@90|offset@90"])
    }
    func testAnEmptiedNoteIsRemoved() throws {
        var t = try recording()
        var writer = NoteWriter()
        try writer.typing("x", at: moment(10), in: &t)
        try writer.typing("", at: moment(11), in: &t)
        XCTAssertNil(writer.openNoteId)
        try writer.finish(in: &t)
        XCTAssertEqual(notes(t), [])
        try writer.typing("  \n ", at: moment(20), in: &t)
        try writer.finish(in: &t)
        XCTAssertEqual(notes(t), [])
        XCTAssertEqual(t.manifest.items.count, 1)      // only the "Recording started" marker
    }
    func testTypingAgainAfterEmptyingStartsAFreshNote() throws {
        var t = try recording()
        var writer = NoteWriter()
        try writer.typing("x", at: moment(10), in: &t)
        try writer.typing("", at: moment(12), in: &t)
        try writer.typing("y", at: moment(30), in: &t)
        try writer.finish(in: &t)
        XCTAssertEqual(notes(t), ["y|at@30|offset@30"])
    }
    func testBlankSpaceAloneDoesNotStartANote() throws {
        var t = try recording()
        var writer = NoteWriter()
        try writer.typing("  ", at: moment(10), in: &t)
        XCTAssertNil(writer.openNoteId)
        try writer.typing("  hello", at: moment(15), in: &t)
        try writer.finish(in: &t)
        XCTAssertEqual(notes(t), ["hello|at@15|offset@15"])
    }
    func testFinishTrimsTheEnds() throws {
        var t = try recording()
        var writer = NoteWriter()
        try writer.typing("  hello \n", at: moment(10), in: &t)
        guard case .text(_, let whileWriting, _) = t.manifest.items[1] else { return XCTFail() }
        XCTAssertEqual(whileWriting, "  hello \n")     // kept as typed while the note is open
        try writer.finish(in: &t)
        XCTAssertEqual(notes(t), ["hello|at@10|offset@10"])
    }
    func testRevisingAnOlderNote() throws {
        var t = try recording()
        var writer = NoteWriter()
        try writer.typing("first", at: moment(10), in: &t)
        let id = try XCTUnwrap(writer.openNoteId)
        try writer.finish(in: &t)
        try writer.revise(id: id, text: " first, corrected ", at: moment(500), in: &t)
        XCTAssertEqual(notes(t), ["first, corrected|at@10|offset@10 changed@500"])
        try writer.revise(id: id, text: "first, corrected", at: moment(600), in: &t)     // no change: not a new edit
        XCTAssertEqual(notes(t), ["first, corrected|at@10|offset@10 changed@500"])
        try writer.revise(id: id, text: "  ", at: moment(700), in: &t)
        XCTAssertEqual(notes(t), [])
        XCTAssertThrowsError(try writer.revise(id: id, text: "x", at: moment(800), in: &t))
    }
    func testFinishWithNothingOpenDoesNothing() throws {
        var t = try recording()
        var writer = NoteWriter()
        let before = t.manifest
        try writer.finish(in: &t)
        XCTAssertEqual(t.manifest, before)
    }
    func testWhileNothingIsRecordingANoteHasNoPlaceOnTheAudio() throws {
        var t = try recording()
        try t.endRecording(by: .pause, at: moment(40))
        var writer = NoteWriter()
        try writer.typing("off the record", at: moment(50), in: &t)
        try writer.finish(in: &t)
        XCTAssertEqual(notes(t), ["off the record|at@50|offset@none"])
    }
}
