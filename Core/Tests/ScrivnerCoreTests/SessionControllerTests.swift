import XCTest
@testable import ScrivnerCore

final class SessionControllerTests: XCTestCase {
    var root: URL!
    var clock: FakeClock!
    var audio: FakeAudio!
    var location: FakeLocation!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("controller-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        clock = FakeClock(); audio = FakeAudio(); location = FakeLocation()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func start(title: String? = "Market visit", locationOn: Bool = true) throws -> SessionController {
        try SessionController.start(title: title, participants: ["P-014"], researcher: nil,
                                    device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                    locationOn: locationOn, in: root, clock: clock, audio: audio, location: location,
                                    ids: SeededIdSource(seed: 21))
    }
    func rows(_ c: SessionController) -> [PageRow] { c.page(style: .twentyFourHour).rows }
    func markers(_ c: SessionController) -> [String] {
        rows(c).compactMap { if case .marker(let text) = $0.content { return text.components(separatedBy: " · ").first }; return nil }
    }
    /// Takes a photo the way the app does: ask for a request, write the file, report it saved.
    @discardableResult
    func snap(_ c: SessionController) throws -> PhotoRequest {
        let request = c.preparePhoto()
        try Data("photo".utf8).write(to: request.url)
        c.photoSaved(request)
        return request
    }
    func onDisk(_ c: SessionController) throws -> Manifest { try SessionStore.load(c.folder) }

    func testStartingASessionRecordsAtOnce() throws {
        let c = try start()
        XCTAssertTrue(c.isRecording)
        XCTAssertEqual(c.folder.url.lastPathComponent.prefix(29), "2026-11-23 1042 Market visit ")
        XCTAssertEqual(audio.started.map(\.lastPathComponent), ["audio-001.m4a"])
        XCTAssertEqual(c.manifest.spans.map(\.file), ["audio/audio-001.m4a"])
        XCTAssertNil(c.manifest.spans[0].endedBy)
        XCTAssertEqual(rows(c).first?.content, .marker("Recording started · local time, UTC+5:45"))
        XCTAssertEqual(try onDisk(c), c.manifest)
        XCTAssertEqual(c.notices, [])
    }
    func testAnUntitledSessionShowsItsDateAndTime() throws {
        let c = try start(title: "  ")
        XCTAssertEqual(c.manifest.title, "")
        XCTAssertEqual(c.page(style: .twentyFourHour).title, "2026-11-23 10:42")
        XCTAssertTrue(c.folder.url.lastPathComponent.hasPrefix("2026-11-23 1042 ["), c.folder.url.lastPathComponent)
        XCTAssertTrue(try String(contentsOf: c.folder.notes, encoding: .utf8).hasPrefix("# 2026-11-23 10:42\n"))
    }
    func testPauseAndResumeMakeTwoSpans() throws {
        let c = try start()
        clock.advance(10); audio.lengthOnStop = 9_950
        c.pause()
        XCTAssertFalse(c.isRecording); XCTAssertFalse(audio.isRunning)
        clock.advance(20)
        c.resume()
        XCTAssertTrue(c.isRecording)
        clock.advance(5); audio.lengthOnStop = 5_000
        c.pause()
        XCTAssertEqual(c.manifest.spans.map(\.durationMs), [9_950, 5_000])
        XCTAssertEqual(c.manifest.spans.map(\.endedBy), [.pause, .pause])
        XCTAssertEqual(audio.started.map(\.lastPathComponent), ["audio-001.m4a", "audio-002.m4a"])
        XCTAssertEqual(markers(c), ["Recording started", "Paused", "Resumed", "Paused"])
        XCTAssertEqual(try onDisk(c), c.manifest)
    }
    func testNotesAndPhotosWhilePausedAreNotOnAudio() throws {
        let c = try start()
        clock.advance(10); c.pause()
        clock.advance(5); c.typing("off the record"); c.finishNote()
        clock.advance(5); try snap(c)
        XCTAssertEqual(rows(c).suffix(2).map(\.isOnAudio), [false, false])
        XCTAssertEqual(rows(c).suffix(2).map(\.time), ["10:42", "10:42"])
    }
    func testInterruptionClosesTheSpanAndResumeOpensANewOne() throws {
        let c = try start()
        clock.advance(30); audio.lengthOnStop = 29_500              // the audio's own length, not the clock's
        c.interruptionBegan(reason: "phone call")
        XCTAssertFalse(c.isRecording)
        XCTAssertEqual(c.manifest.spans[0].endedBy, .interruption)
        XCTAssertEqual(c.manifest.spans[0].durationMs, 29_500)
        XCTAssertEqual(rows(c).last?.content, .marker("Interrupted (phone call) · local time, UTC+5:45"))
        clock.advance(20); c.typing("she took a call"); c.finishNote()
        XCTAssertEqual(rows(c).last?.isOnAudio, false)
        clock.advance(40)
        c.interruptionEnded()
        XCTAssertTrue(c.isRecording)
        XCTAssertEqual(c.manifest.spans.count, 2)
        XCTAssertEqual(markers(c), ["Recording started", "Interrupted (phone call)", "Resumed"])
        XCTAssertEqual(c.manifest.problems(finished: false), [])
    }
    func testAnInterruptionDoesNotUndoAPause() throws {
        let c = try start()
        clock.advance(5); c.pause()
        c.interruptionBegan(reason: "phone call"); c.interruptionEnded()
        XCTAssertFalse(c.isRecording)
        // Nor does it resume when the owner pressed pause during the interruption.
        c.resume(); clock.advance(5)
        c.interruptionBegan(reason: "phone call")
        c.pause()
        c.interruptionEnded()
        XCTAssertFalse(c.isRecording)
        XCTAssertEqual(c.manifest.spans.count, 2)
    }
    func testTakingAPhoto() throws {
        let c = try start()
        clock.advance(185); location.fix(at: clock.now().wall)
        let request = try snap(c)
        XCTAssertEqual(request.file, "photos/photo-0001.heic")
        XCTAssertEqual(request.url, c.folder.url(forRelativePath: "photos/photo-0001.heic"))
        XCTAssertEqual(request.place, GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: 5))
        guard case .photo(let p, let file, _, let gps) = try XCTUnwrap(c.manifest.items.last) else { return XCTFail() }
        XCTAssertEqual(file, "photos/photo-0001.heic"); XCTAssertEqual(gps, request.place)
        XCTAssertEqual(p.offsetMs, 185_000); XCTAssertEqual(p.at, request.moment.wall)
        XCTAssertEqual(try onDisk(c), c.manifest)
    }
    func testTwoPhotosInQuickSuccessionGetDifferentNames() throws {
        let c = try start()
        let first = c.preparePhoto(), second = c.preparePhoto()
        XCTAssertEqual([first.file, second.file], ["photos/photo-0001.heic", "photos/photo-0002.heic"])
        try Data("b".utf8).write(to: second.url); c.photoSaved(second)
        try Data("a".utf8).write(to: first.url); c.photoSaved(first)
        XCTAssertEqual(c.preparePhoto().file, "photos/photo-0003.heic")
    }
    func testAPhotoThatArrivesAfterAPauseIsPlacedWhereItWasTaken() throws {
        let c = try start()
        clock.advance(9)
        let request = c.preparePhoto()              // the shutter, 9 s into the recording
        clock.advance(1); audio.lengthOnStop = 10_000
        c.pause()                                   // the file is still being written
        clock.advance(1)
        try Data("photo".utf8).write(to: request.url); c.photoSaved(request)
        guard case .photo(let p, _, _, _) = try XCTUnwrap(c.manifest.items.last) else { return XCTFail() }
        XCTAssertEqual(p.spanId, c.manifest.spans[0].id); XCTAssertEqual(p.offsetMs, 9_000)
        XCTAssertEqual(c.manifest.problems(finished: false), [])
    }
    func testAPhotoCanBeAJPEG() throws {
        // The simulator cannot always write HEIC; the stand-in camera then writes a JPEG.
        let c = try start()
        let jpeg = c.preparePhoto(fileExtension: "jpg")
        XCTAssertEqual(jpeg.file, "photos/photo-0001.jpg")
        try Data("jpeg".utf8).write(to: jpeg.url); c.photoSaved(jpeg)
        XCTAssertEqual(c.preparePhoto().file, "photos/photo-0002.heic")       // one run of numbers, whatever the ending
    }
    func testIsFinished() throws {
        let c = try start()
        XCTAssertFalse(c.isFinished)
        clock.advance(5); c.pause()
        XCTAssertFalse(c.isFinished)                                          // closed, but no checksums yet
        clock.advance(5); c.stop()
        XCTAssertTrue(c.isFinished)
        clock.advance(5); c.resume()
        XCTAssertFalse(c.isFinished)
    }
    func testOpenNoteText() throws {
        let c = try start()
        XCTAssertNil(c.openNoteText)
        clock.advance(1); c.typing("half a tho")
        XCTAssertEqual(c.openNoteText, "half a tho")
        XCTAssertEqual(c.openNoteId, c.page(style: .twentyFourHour).rows.last?.id)
        c.finishNote()
        XCTAssertNil(c.openNoteText); XCTAssertNil(c.openNoteId)
    }
    func testNoPlaceAfterLocationIsSwitchedOff() throws {
        let c = try start()
        clock.advance(5); location.fix(at: clock.now().wall)
        c.setLocation(on: false)
        XCTAssertFalse(c.isLocationOn)
        clock.advance(1); location.fix(at: clock.now().wall)      // the chip still has a fresh fix
        let request = try snap(c)
        XCTAssertNil(request.place)
        guard case .photo(_, _, _, let gps) = try XCTUnwrap(c.manifest.items.last) else { return XCTFail() }
        XCTAssertNil(gps)
        XCTAssertEqual(markers(c), ["Recording started", "Location off"])
        c.setLocation(on: false)                                  // saying it twice writes one marker
        c.setLocation(on: true)
        XCTAssertEqual(markers(c), ["Recording started", "Location off", "Location on"])
        XCTAssertNotNil(try snap(c).place)
    }
    func testAPhotoThatFailsIsNotListed() throws {
        let c = try start()
        let request = c.preparePhoto()
        c.photoFailed(request, reason: "the camera is in use")
        XCTAssertEqual(c.manifest.items.map(\.kind), ["marker"])
        XCTAssertEqual(c.notices, [.couldNotTakePhoto("the camera is in use")])
        c.clearNotices()
        XCTAssertEqual(c.notices, [])
        // Reported as saved, but the file is not there: treated as a failure too.
        c.photoSaved(c.preparePhoto())
        XCTAssertEqual(c.manifest.items.map(\.kind), ["marker"])
        XCTAssertEqual(c.notices.count, 1)
    }
    func testStartLocationArrivesLate() throws {
        let c = try start()
        XCTAssertNil(c.manifest.startLocation)
        clock.advance(8); location.fix(at: clock.now().wall)
        c.locationFixArrived()
        XCTAssertEqual(c.manifest.startLocation, GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: 5))
        clock.advance(30)
        location.latest = LocationFix(lat: 1, lon: 2, alt: nil, horizontalAccuracyM: 5, verticalAccuracyM: nil, at: clock.now().wall)
        c.locationFixArrived()
        XCTAssertEqual(c.manifest.startLocation?.lat, 27.7046)       // set once
        XCTAssertEqual(try onDisk(c), c.manifest)
    }
    func testAStartLocationIsNotTakenLongAfterTheStartOrWithLocationOff() throws {
        let late = try start()
        clock.advance(121); location.fix(at: clock.now().wall)
        late.locationFixArrived()
        XCTAssertNil(late.manifest.startLocation)                    // two minutes on, it is no longer where the session began
        clock = FakeClock(); clock.wallShiftMs = 3_600_000; audio = FakeAudio()
        let off = try start(locationOn: false)
        location.fix(at: clock.now().wall)
        off.locationFixArrived()
        XCTAssertNil(off.manifest.startLocation)
    }
    func testStaleOrInvalidFixesAreNotStamped() {
        let now = Instant(iso: "2026-11-23T05:00:00.000Z")!
        func fix(age: Int64 = 0, h: Double = 5, v: Double? = 3) -> LocationFix {
            LocationFix(lat: 27.7046, lon: 85.3076, alt: 1300, horizontalAccuracyM: h, verticalAccuracyM: v, at: now.adding(milliseconds: -age))
        }
        XCTAssertEqual(Place.stamp(from: fix(), enabled: true, now: now), GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: 5))
        XCTAssertNil(Place.stamp(from: fix(age: 61_000), enabled: true, now: now))
        XCTAssertNotNil(Place.stamp(from: fix(age: 60_000), enabled: true, now: now))
        XCTAssertNil(Place.stamp(from: fix(h: -1), enabled: true, now: now))
        XCTAssertEqual(Place.stamp(from: fix(v: -1), enabled: true, now: now)?.alt, nil)
        XCTAssertEqual(Place.stamp(from: fix(v: nil), enabled: true, now: now)?.alt, nil)
        XCTAssertNil(Place.stamp(from: fix(), enabled: false, now: now))
        XCTAssertNil(Place.stamp(from: nil, enabled: true, now: now))
        XCTAssertNil(Place.stamp(from: LocationFix(lat: .nan, lon: 0, alt: nil, horizontalAccuracyM: 5, verticalAccuracyM: nil, at: now), enabled: true, now: now))
    }
    func testStopFinishesTheSession() throws {
        let c = try start()
        clock.advance(20); try snap(c)
        clock.advance(5); c.typing("still typing when stop is pressed")
        clock.advance(5); audio.lengthOnStop = 30_000
        c.stop()
        XCTAssertFalse(c.isRecording)
        XCTAssertEqual(c.notices, [])
        XCTAssertEqual(c.manifest.problems(finished: true), [])
        XCTAssertEqual(markers(c), ["Recording started", "Stopped"])
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
        XCTAssertEqual(try onDisk(c), c.manifest)
    }
    func testStoppingWhilePausedStillMarksTheEnd() throws {
        let c = try start()
        clock.advance(10); c.pause()
        clock.advance(60); c.stop()
        XCTAssertEqual(markers(c), ["Recording started", "Paused", "Stopped"])
        XCTAssertEqual(rows(c).last?.isOnAudio, false)
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
    }
    func testResumingAfterStopClearsChecksums() throws {
        let c = try start()
        clock.advance(10); c.stop()
        XCTAssertNotNil(c.manifest.spans[0].sha256)
        clock.advance(60); c.resume()
        XCTAssertTrue(c.isRecording)
        XCTAssertEqual(c.manifest.spans.map(\.sha256), [nil, nil])
        XCTAssertEqual(try onDisk(c), c.manifest)
        clock.advance(10); c.stop()
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
        XCTAssertEqual(markers(c), ["Recording started", "Stopped", "Resumed", "Stopped"])
    }
    func testAddingANoteAfterStopKeepsTheSessionFinished() throws {
        let c = try start()
        clock.advance(10); c.stop()
        clock.advance(600); c.typing("added that evening"); c.finishNote()
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])      // still finished: the checksums are for the media, which did not change
        XCTAssertEqual(rows(c).last?.content, .text("added that evening", edited: false))
    }
    func testEverythingIsSavedAsItHappens() throws {
        let c = try start()
        clock.advance(3); c.typing("a note"); c.finishNote()
        XCTAssertEqual(try onDisk(c), c.manifest)
        clock.advance(3); try snap(c)
        XCTAssertEqual(try onDisk(c), c.manifest)
        clock.advance(3); c.setParticipants("P-014, P-015  P-016")
        XCTAssertEqual(try onDisk(c).participants, ["P-014", "P-015", "P-016"])
        clock.advance(3); c.pause()
        XCTAssertEqual(try onDisk(c), c.manifest)
    }
    func testTypingIsSavedAtLeastEveryTwoSeconds() throws {
        let c = try start()
        clock.advance(1); c.typing("a")
        let afterFirst = try onDisk(c)
        XCTAssertEqual(afterFirst.items.count, 2)                       // the first keystroke of a note is saved at once
        clock.advance(0.5); c.typing("ab")
        clock.advance(0.5); c.typing("abc")
        XCTAssertEqual(try onDisk(c), afterFirst)                       // not every keystroke
        clock.advance(1.5); c.typing("abcd")
        XCTAssertEqual(try onDisk(c), c.manifest)                       // but never more than two seconds behind
        clock.advance(0.2); c.typing("abcde")
        c.saveIfNeeded()
        XCTAssertEqual(try onDisk(c), c.manifest)
    }
    func testASaveThatFailsIsReportedAndRetried() throws {
        let c = try start()
        let away = root.appendingPathComponent("moved-away")
        try FileManager.default.moveItem(at: c.folder.url, to: away)    // the folder cannot be written to
        clock.advance(2); c.typing("typed while saving fails"); c.finishNote()
        XCTAssertEqual(c.notices.count, 1)
        guard case .couldNotSave = c.notices[0] else { return XCTFail("\(c.notices)") }
        XCTAssertTrue(c.isRecording)                                    // recording is not dropped
        try FileManager.default.moveItem(at: away, to: c.folder.url)
        clock.advance(2); c.typing("and after"); c.finishNote()
        XCTAssertEqual(try onDisk(c), c.manifest)
        XCTAssertEqual(c.notices.count, 1)                              // no second complaint once it works again
    }
    func testRenamingWaitsUntilNothingIsBeingRecorded() throws {
        let c = try start(title: nil)
        let before = c.folder.url
        clock.advance(5); c.setTitle("Market visit")
        XCTAssertEqual(c.page(style: .twentyFourHour).title, "Market visit")
        XCTAssertEqual(c.folder.url, before)                            // files are being written into it
        clock.advance(5); c.pause()
        XCTAssertTrue(c.folder.url.lastPathComponent.hasPrefix("2026-11-23 1042 Market visit ["), c.folder.url.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: before.path))
        XCTAssertEqual(try onDisk(c).title, "Market visit")
        clock.advance(5); c.resume()
        XCTAssertEqual(audio.started.last?.deletingLastPathComponent().deletingLastPathComponent(), c.folder.url)
        clock.advance(5); c.stop()
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
    }
    func testTheCounter() throws {
        let c = try start()
        clock.advance(10); audio.lengthOnStop = 9_950
        XCTAssertEqual(c.recordedMilliseconds, 10_000)                  // while recording: by the clock
        c.pause()
        XCTAssertEqual(c.recordedMilliseconds, 9_950)                   // once closed: the audio's own length
        clock.advance(100); c.resume()
        clock.advance(5)
        XCTAssertEqual(c.recordedMilliseconds, 14_950)
    }
    func testNoMicrophone() throws {
        audio.failNextStart = true
        let c = try start()
        XCTAssertFalse(c.isRecording)
        XCTAssertEqual(c.manifest.spans, [])
        XCTAssertEqual(c.notices.count, 1)
        guard case .couldNotRecord = c.notices[0] else { return XCTFail("\(c.notices)") }
        XCTAssertEqual(try onDisk(c), c.manifest)
        clock.advance(5); c.resume()
        XCTAssertTrue(c.isRecording)
        XCTAssertEqual(markers(c), ["Recording started"])
    }
}
