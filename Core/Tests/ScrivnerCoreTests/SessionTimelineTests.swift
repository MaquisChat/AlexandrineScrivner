import XCTest
@testable import ScrivnerCore

final class SessionTimelineTests: XCTestCase {
    let zero = UTCOffset(seconds: 0)
    let t0 = Instant(iso: "2026-11-23T10:42:10.120Z")!
    func moment(_ seconds: Double, wallShiftMs: Int64 = 0, offset: UTCOffset? = nil, zone: String = "Europe/Lisbon") -> Moment {
        Moment(host: 1000 + seconds, wall: t0.adding(milliseconds: Int64(seconds * 1000) + wallShiftMs),
               utcOffset: offset ?? zero, timeZone: zone)
    }
    func newTimeline() -> SessionTimeline {
        SessionTimeline(title: "Market visit", participants: ["P-014"], researcher: nil,
                        device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                        startLocation: nil, at: moment(0), ids: SeededIdSource(seed: 1))
    }

    func testItemsArePlacedOnTheOpenSpan() throws {
        var t = newTimeline()
        let span = try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.addText("P-014 has run the stall since 2009.", at: moment(65))
        try t.addPhoto(file: "photos/photo-0001.heic", gps: nil, at: moment(185))
        XCTAssertEqual(t.manifest.items.map(\.kind), ["marker", "text", "photo"])
        XCTAssertEqual(t.manifest.items.map(\.placement.offsetMs), [0, 65_000, 185_000])
        XCTAssertEqual(Set(t.manifest.items.map(\.placement.spanId)), [span])
        XCTAssertEqual(t.manifest.items[1].placement.at.iso, "2026-11-23T10:43:15.120Z")
        XCTAssertTrue(t.isRecording)
    }
    func testPauseResumeStopMakeSpansAndMarkers() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.endRecording(by: .pause, at: moment(551))
        try t.addText("off the record", at: moment(600))
        try t.startRecording(file: "audio/audio-002.m4a", at: moment(700))
        try t.endRecording(by: .interruption, detail: "phone call", at: moment(750))
        try t.startRecording(file: "audio/audio-003.m4a", at: moment(800))
        try t.endRecording(by: .stop, audioDurationMs: 99_950, at: moment(900))
        XCTAssertEqual(t.manifest.spans.map(\.durationMs), [551_000, 50_000, 99_950])
        XCTAssertEqual(t.manifest.spans.map(\.endedBy), [.pause, .interruption, .stop])
        let markers: [String] = t.manifest.items.compactMap { if case .marker(_, let type, _) = $0 { return type.rawValue }; return nil }
        XCTAssertEqual(markers, ["recording-started", "paused", "resumed", "interrupted", "resumed", "stopped"])
        guard case .text(let p, _, _) = t.manifest.items[2] else { return XCTFail() }
        XCTAssertNil(p.spanId); XCTAssertNil(p.offsetMs)
        guard case .marker(_, _, let detail) = t.manifest.items[4] else { return XCTFail() }
        XCTAssertEqual(detail, "phone call")
        XCTAssertFalse(t.isRecording)
    }
    func testClipLengthAndSound() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        let loud = try t.startClip(file: "video/clip-0001.mov", gps: nil, at: moment(430))
        try t.endClip(id: loud, by: .user, at: moment(478))
        try t.endRecording(by: .pause, at: moment(500))
        let quiet = try t.startClip(file: "video/clip-0002.mov", gps: nil, at: moment(510))
        try t.endClip(id: quiet, by: .background, at: moment(520))
        guard case .video(let p1, let d1, let e1, let s1, _, _, _) = t.manifest.items[1],
              case .video(let p2, let d2, let e2, let s2, _, _, _) = t.manifest.items[3] else { return XCTFail() }
        XCTAssertEqual([p1.offsetMs, d1], [430_000, 48_000]); XCTAssertEqual(e1, .user); XCTAssertTrue(s1)
        XCTAssertNil(p2.spanId); XCTAssertEqual(d2, 10_000); XCTAssertEqual(e2, .background); XCTAssertFalse(s2)
        XCTAssertThrowsError(try t.endClip(id: loud, by: .user, at: moment(530))) { XCTAssertEqual($0 as? TimelineError, .clipAlreadyEnded(loud)) }
        XCTAssertThrowsError(try t.endClip(id: "nope", by: .user, at: moment(530))) { XCTAssertEqual($0 as? TimelineError, .noSuchItem("nope")) }
    }
    func testWallClockJumpDoesNotMoveOffsets() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.addText("before", at: moment(60))
        try t.addText("after the clock went back an hour", at: moment(120, wallShiftMs: -3_600_000))
        try t.endRecording(by: .stop, at: moment(180, wallShiftMs: -3_600_000))
        XCTAssertEqual(t.manifest.items.map(\.placement.offsetMs), [0, 60_000, 120_000, 180_000])
        XCTAssertEqual(t.manifest.spans[0].durationMs, 180_000)
        XCTAssertEqual(t.manifest.items[2].placement.at.iso, "2026-11-23T09:44:10.120Z")
    }
    func testTimeZoneChangeIsKeptPerItem() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.addText("landed", at: moment(60, offset: UTCOffset(seconds: 3600), zone: "Europe/Madrid"))
        XCTAssertEqual(t.manifest.items.map(\.placement.utcOffset.string), ["+00:00", "+01:00"])
        XCTAssertEqual(t.manifest.spans[0].timeZone, "Europe/Lisbon")
        XCTAssertEqual(t.manifest.items[1].placement.offsetMs, 60_000)
    }
    func testEditKeepsTheOriginalTime() throws {
        var t = newTimeline()
        let id = try t.addText("first", at: moment(10))
        try t.editText(id: id, text: "first, corrected", at: moment(90))
        guard case .text(let p, let text, let modified) = t.manifest.items[0] else { return XCTFail() }
        XCTAssertEqual(text, "first, corrected")
        XCTAssertEqual(p.at, t0.adding(milliseconds: 10_000)); XCTAssertEqual(modified, t0.adding(milliseconds: 90_000))
    }
    func testLocationMarkersAndRecordingErrors() throws {
        var t = newTimeline()
        try t.setLocation(enabled: false, at: moment(5))
        try t.setLocation(enabled: true, at: moment(6))
        let markers: [String] = t.manifest.items.compactMap { if case .marker(_, let type, _) = $0 { return type.rawValue }; return nil }
        XCTAssertEqual(markers, ["location-off", "location-on"])
        XCTAssertThrowsError(try t.endRecording(by: .stop, at: moment(7))) { XCTAssertEqual($0 as? TimelineError, .notRecording) }
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(8))
        XCTAssertThrowsError(try t.startRecording(file: "audio/audio-002.m4a", at: moment(9))) { XCTAssertEqual($0 as? TimelineError, .alreadyRecording) }
    }
    func testCrashRecoveryClosesTheOpenSpanAndClip() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.startClip(file: "video/clip-0001.mov", gps: nil, at: moment(30))
        var back = SessionTimeline(resuming: t.manifest, ids: SeededIdSource(seed: 2))
        XCTAssertTrue(back.needsRecovery)
        XCTAssertThrowsError(try back.addText("x", at: moment(500))) { XCTAssertEqual($0 as? TimelineError, .needsRecovery) }
        back.recoverAfterCrash(spanDurationMs: 42_000, at: moment(500))
        XCTAssertFalse(back.needsRecovery); XCTAssertFalse(back.isRecording)
        XCTAssertEqual(back.manifest.spans[0].durationMs, 42_000); XCTAssertEqual(back.manifest.spans[0].endedBy, .crashRecovered)
        guard case .video(_, let d, let e, _, _, _, _) = back.manifest.items[1],
              case .marker(let p, let type, let detail) = back.manifest.items[2] else { return XCTFail() }
        XCTAssertNil(d); XCTAssertEqual(e, .interruption)
        XCTAssertEqual(type, .interrupted); XCTAssertEqual(detail, "crash-recovered"); XCTAssertNil(p.spanId)
        try back.startRecording(file: "audio/audio-002.m4a", at: moment(510))
        XCTAssertEqual(back.manifest.spans.count, 2)
    }
    func testLoadedOpenSessionNeedsRecovery() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.endRecording(by: .stop, at: moment(10))
        XCTAssertFalse(SessionTimeline(resuming: t.manifest, ids: SeededIdSource(seed: 2)).needsRecovery)
    }
    func testIdsAreValidAndUnique() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.addText("a", at: moment(1)); try t.addText("b", at: moment(1))
        let ids = [t.manifest.id] + t.manifest.spans.map(\.id) + t.manifest.items.map(\.placement.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy(UUIDv7.isValid))
    }
}
