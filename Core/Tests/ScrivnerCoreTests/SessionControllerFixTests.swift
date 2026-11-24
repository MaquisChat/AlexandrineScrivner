import XCTest
@testable import ScrivnerCore

/// Sequences an independent review found the controller got wrong. Each is pinned here.
final class SessionControllerFixTests: XCTestCase {
    var root: URL!
    var clock: FakeClock!
    var audio: FakeAudio!
    var location: FakeLocation!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fixes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        clock = FakeClock(); audio = FakeAudio(); location = FakeLocation()
        audio.clock = clock
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func start(locationOn: Bool = false, title: String? = "Market visit") throws -> SessionController {
        try SessionController.start(title: title, participants: [], researcher: nil,
                                    device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                    locationOn: locationOn, in: root, clock: clock, audio: audio, location: location,
                                    ids: SeededIdSource(seed: 41))
    }
    func reopen(_ folder: SessionFolder, locationOn: Bool = false) throws -> SessionController {
        audio = FakeAudio()
        return try SessionController.open(folder, locationOn: locationOn, clock: clock, audio: audio, location: location,
                                          ids: SeededIdSource(seed: 42), audioLength: { _ in 10_000 })
    }
    @discardableResult
    func snap(_ c: SessionController) throws -> PhotoRequest {
        let request = c.preparePhoto()
        try Data("photo".utf8).write(to: request.url)
        c.photoSaved(request)
        return request
    }
    func markers(_ c: SessionController) -> [String] {
        c.page(style: .twentyFourHour).rows.compactMap {
            if case .marker(let text) = $0.content { return text.components(separatedBy: " · ").first }
            return nil
        }
    }

    // MARK: - A session that could never be finished

    func testAListedFileThatHasGoneDoesNotBlockFinishing() throws {
        let c = try start()
        clock.advance(5); let photo = try snap(c)
        clock.advance(5); c.pause()
        try FileManager.default.removeItem(at: photo.url)          // deleted in the Files app
        clock.advance(5); c.stop()
        XCTAssertTrue(c.isFinished)
        XCTAssertEqual(c.notices, [.filesMissing(["photos/photo-0001.heic"])])
        XCTAssertEqual(c.manifest.items.map(\.kind), ["marker", "marker", "marker", "marker"])   // location off, started, paused, stopped
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
    }
    func testASessionLeftUnfinishedByAMissingFileIsRepairedOnOpening() throws {
        let c = try start()
        clock.advance(5); let photo = try snap(c)
        clock.advance(5); c.pause()
        try FileManager.default.removeItem(at: photo.url)
        let again = try reopen(c.folder)
        XCTAssertEqual(again.notices, [.filesMissing(["photos/photo-0001.heic"])])
        again.stop()
        XCTAssertTrue(again.isFinished)
        XCTAssertEqual(SessionCheck.folder(again.folder).findings, [])
    }
    func testStoppingTwiceWritesOneStoppedMarker() throws {
        let c = try start()
        clock.advance(5); c.stop()
        let after = c.manifest
        clock.advance(5); c.stop()
        clock.advance(5); c.stop()
        XCTAssertEqual(c.manifest, after)
        XCTAssertEqual(markers(c).filter { $0 == "Stopped" }.count, 1)
    }

    // MARK: - Location

    func testLocationStaysOffWhenASessionIsReopened() throws {
        let c = try start(locationOn: true)
        clock.advance(5); c.setLocation(on: false)
        clock.advance(5); c.stop()
        let again = try reopen(c.folder, locationOn: true)         // the app's setting is on
        XCTAssertFalse(again.isLocationOn)                         // but this session was switched off
        clock.advance(5); location.fix(at: clock.now().wall)
        XCTAssertNil(again.preparePhoto().place)
        XCTAssertEqual(markers(again).filter { $0.hasPrefix("Location") }, ["Location off"])
    }
    func testASessionStartedWithLocationOffSaysSo() throws {
        let c = try start(locationOn: false)
        XCTAssertEqual(markers(c), ["Recording started", "Location off"])
        clock.advance(5); c.stop()
        XCTAssertFalse(try reopen(c.folder, locationOn: true).isLocationOn)
    }
    func testTurningTheSettingOffAppliesWhenASessionIsReopened() throws {
        let c = try start(locationOn: true)
        clock.advance(5); c.stop()
        let again = try reopen(c.folder, locationOn: false)        // the setting was turned off since
        XCTAssertFalse(again.isLocationOn)
        clock.advance(5); location.fix(at: clock.now().wall)
        let request = try snap(again)
        XCTAssertNil(request.place)
        XCTAssertEqual(markers(again).last, "Location off")        // and the page says so, before the photo
        guard case .marker = again.manifest.items[again.manifest.items.count - 2],
              case .photo = again.manifest.items[again.manifest.items.count - 1] else {
            return XCTFail("the line comes before the photo it explains")
        }
        XCTAssertTrue(again.isFinished)                            // a marker changes no media
    }
    func testOpeningASessionOnlyToReadItChangesNothing() throws {
        let c = try start(locationOn: true)
        clock.advance(5); c.stop()
        let before = try Data(contentsOf: c.folder.sessionJSON)
        let again = try reopen(c.folder, locationOn: false)        // the setting was turned off since
        clock.advance(60); again.saveIfNeeded()
        XCTAssertEqual(again.manifest, c.manifest)
        XCTAssertEqual(try Data(contentsOf: c.folder.sessionJSON), before, "reading a session must not make it look changed")
        XCTAssertFalse(again.hasUnsavedChanges)
    }
    func testTheLocationOffLineComesBeforeRecordingStartsAgain() throws {
        let c = try start(locationOn: true)
        clock.advance(5); c.stop()
        let again = try reopen(c.folder, locationOn: false)
        clock.advance(5); again.resume()
        XCTAssertEqual(Array(markers(again).suffix(2)), ["Location off", "Resumed"])
        XCTAssertEqual(markers(again).filter { $0 == "Location off" }.count, 1)
        clock.advance(5); again.pause(); clock.advance(5); again.resume()
        XCTAssertEqual(markers(again).filter { $0 == "Location off" }.count, 1, "it is said once")
    }
    func testTurningLocationBackOnBeforeAnythingIsAddedWritesNothing() throws {
        let c = try start(locationOn: true)
        clock.advance(5); c.stop()
        let again = try reopen(c.folder, locationOn: false)
        clock.advance(5); again.setLocation(on: true)              // the owner wants it for this session after all
        XCTAssertTrue(again.isLocationOn)
        XCTAssertEqual(again.manifest, c.manifest, "the session never stopped saying on")
        clock.advance(5); location.fix(at: clock.now().wall)
        XCTAssertNotNil(again.preparePhoto().place)
    }
    func testStartLocationIsNotSetLaterOrBackwards() throws {
        // Off at the start and switched on 30 s later: where the session began is not known.
        let off = try start(locationOn: false)
        clock.advance(30); off.setLocation(on: true); location.fix(at: clock.now().wall)
        off.locationFixArrived()
        XCTAssertNil(off.manifest.startLocation)
        // A reopened session never gains one, whatever the clock says.
        clock = FakeClock(); audio = FakeAudio(); location = FakeLocation()
        let on = try start(locationOn: true, title: "Second")
        clock.advance(5); on.stop()
        clock.wallShiftMs = -3_600_000
        let again = try reopen(on.folder, locationOn: true)
        location.fix(at: clock.now().wall); again.locationFixArrived()
        XCTAssertNil(again.manifest.startLocation)
    }

    // MARK: - Photos

    func testPhotoNumbersAreNeverReused() throws {
        let c = try start()
        let a = c.preparePhoto(), b = c.preparePhoto()
        c.photoFailed(a, reason: "the camera was busy")
        let third = c.preparePhoto()
        XCTAssertEqual([a.file, b.file, third.file], ["photos/photo-0001.heic", "photos/photo-0002.heic", "photos/photo-0003.heic"])
        try Data("b".utf8).write(to: b.url); c.photoSaved(b)
        try Data("c".utf8).write(to: third.url); c.photoSaved(third)
        c.photoSaved(third)                                        // reported twice: listed once
        XCTAssertEqual(c.manifest.items.filter { $0.kind == "photo" }.count, 2)
        clock.advance(5); c.stop()
        XCTAssertTrue(c.isFinished)
    }
    func testNamesOfFilesAlreadyOnDiskAreNotHandedOutAgain() throws {
        let c = try start()
        clock.advance(5)
        let orphan = c.preparePhoto()
        try Data("written, never reported".utf8).write(to: orphan.url)   // the app is killed before photoSaved
        clock.advance(5); c.typing("x"); c.finishNote()
        let again = try reopen(c.folder)
        XCTAssertEqual(again.notices, [.recovered(dropped: []), .filesNotListed(["photos/photo-0001.heic"])])
        XCTAssertEqual(again.preparePhoto().file, "photos/photo-0002.heic")
        // The same for audio: a recording whose file exists but was never listed.
        try Data("orphan audio".utf8).write(to: again.folder.url(forRelativePath: "audio/audio-002.m4a"))
        clock.advance(5); again.resume()
        XCTAssertEqual(audio.started.map(\.lastPathComponent), ["audio-003.m4a"])
        XCTAssertEqual(try Data(contentsOf: orphan.url), Data("written, never reported".utf8))
    }
    func testAPhotoThatArrivesAfterStopKeepsTheSessionFinished() throws {
        let c = try start(title: nil)
        clock.advance(5); c.setTitle("Market visit")               // the folder is renamed once nothing is in flight
        let request = c.preparePhoto()
        clock.advance(0.2); c.stop()
        XCTAssertFalse(c.folder.url.lastPathComponent.contains("Market visit"))
        try Data("photo".utf8).write(to: request.url); c.photoSaved(request)
        XCTAssertTrue(c.isFinished)
        XCTAssertTrue(c.folder.url.lastPathComponent.contains("Market visit"), c.folder.url.lastPathComponent)
        XCTAssertEqual(c.notices, [])
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
    }
    func testAFolderOfASessionIsRecreatedIfItWasRemoved() throws {
        let c = try start()
        try FileManager.default.removeItem(at: c.folder.url.appendingPathComponent("photos"))
        clock.advance(5); try snap(c)
        XCTAssertEqual(c.manifest.items.filter { $0.kind == "photo" }.count, 1)
    }

    // MARK: - Interruptions

    func testRecordingIsTriedAgainUntilTheMicrophoneComesBack() throws {
        let c = try start()
        clock.advance(10); c.interruptionBegan(reason: "phone call")
        XCTAssertEqual(c.recorderState, .interrupted("phone call"))
        audio.failNextStart = true
        clock.advance(30); c.interruptionEnded()                   // too soon: the microphone is still taken
        XCTAssertFalse(c.isRecording)
        XCTAssertEqual(c.recorderState, .interrupted("phone call"))
        clock.advance(5); c.interruptionEnded()                    // tried again, as the app will on a timer
        XCTAssertTrue(c.isRecording)
        XCTAssertEqual(c.recorderState, .recording)
    }
    func testResumeTappedDuringAnInterruptionStillResumesAfterwards() throws {
        let c = try start()
        clock.advance(10); c.interruptionBegan(reason: "phone call")
        audio.failNextStart = true
        clock.advance(5); c.resume()                               // the owner taps Resume mid-call; the microphone is busy
        XCTAssertFalse(c.isRecording)
        c.clearNotices()
        clock.advance(30); c.interruptionEnded()
        XCTAssertTrue(c.isRecording)
    }
    func testRecorderStates() throws {
        let c = try start()
        XCTAssertEqual(c.recorderState, .recording)
        clock.advance(5); c.pause()
        XCTAssertEqual(c.recorderState, .paused)
        c.interruptionEnded()                                      // nothing to resume: the owner paused
        XCTAssertEqual(c.recorderState, .paused)
        clock.advance(5); c.stop()
        XCTAssertEqual(c.recorderState, .stopped)
        audio.failNextStart = true
        clock.advance(5); c.resume()                               // no microphone: still finished, and still wanting to record
        XCTAssertTrue(c.isFinished)
        XCTAssertEqual(c.recorderState, .interrupted("the microphone is not available"))
        clock.advance(5); c.interruptionEnded()
        XCTAssertEqual(c.recorderState, .recording)
        XCTAssertFalse(c.isFinished)
    }
    func testTheSpanBeginsWhenTheRecorderSaysItBegan() throws {
        audio.startDelay = 0.25                                    // the microphone takes a moment to start
        let c = try start()
        XCTAssertEqual(c.manifest.spans[0].startedAt, clock.start.adding(milliseconds: 250))
        clock.advance(10); c.typing("ten seconds after pressing start"); c.finishNote()
        XCTAssertEqual(c.manifest.items.last?.placement.offsetMs, 9_750)   // on the audio's own timeline
    }

    // MARK: - After a crash

    func testTheCrashMarkerCarriesTheTimeOfTheCutOff() throws {
        let c = try start()
        clock.advance(40); c.typing("the last thing typed"); c.finishNote()
        clock.advance(72_000); clock.offset = UTCOffset(string: "+01:00")!; clock.zone = "Europe/Paris"   // reopened 20 hours later, elsewhere
        let again = try reopen(c.folder)
        let last = try XCTUnwrap(again.page(style: .twentyFourHour).rows.last)
        XCTAssertEqual(last.content, .marker("Interrupted (the app was closed unexpectedly) · local time, UTC+5:45"))
        XCTAssertEqual(last.time, "10:42")                         // when it was cut off, where it was cut off
    }

    // MARK: - Notes

    func testRevisingSomethingThatIsNotANoteDoesNothing() throws {
        let c = try start()
        clock.advance(5); let photo = try snap(c)
        let photoId = try XCTUnwrap(c.manifest.items.last?.placement.id)
        c.revise(noteId: photoId, text: " ")
        XCTAssertEqual(c.manifest.items.filter { $0.kind == "photo" }.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: photo.url.path))
    }
    func testTypingGoesOnAfterTheOpenNoteWasEmptiedElsewhere() throws {
        let c = try start()
        clock.advance(5); c.typing("open note")
        let id = try XCTUnwrap(c.openNoteId)
        c.revise(noteId: id, text: "")                             // emptied through the other route
        c.clearNotices()
        clock.advance(5); c.typing("fresh words")
        c.finishNote()
        XCTAssertEqual(c.notices, [])
        guard case .text(let p, let text, _) = try XCTUnwrap(c.manifest.items.last) else { return XCTFail() }
        XCTAssertEqual(text, "fresh words"); XCTAssertEqual(p.offsetMs, 10_000)
    }

    // MARK: - Smaller things

    func testAFailedResumeLeavesAFinishedSessionFinished() throws {
        let c = try start()
        clock.advance(5); c.stop()
        audio.failNextStart = true
        clock.advance(5); c.resume()
        XCTAssertTrue(c.isFinished)
    }
    func testUnsavedChangesAreSaidForAsLongAsTheyLast() throws {
        let c = try start()
        XCTAssertFalse(c.hasUnsavedChanges)
        let away = root.appendingPathComponent("moved-away")
        try FileManager.default.moveItem(at: c.folder.url, to: away)
        clock.advance(3); c.typing("a"); c.finishNote()
        XCTAssertTrue(c.hasUnsavedChanges)
        c.clearNotices()
        clock.advance(3); c.typing("b"); c.finishNote()
        XCTAssertTrue(c.hasUnsavedChanges)                          // still true after the notice was dismissed
        try FileManager.default.moveItem(at: away, to: c.folder.url)
        c.saveIfNeeded()
        XCTAssertFalse(c.hasUnsavedChanges)
    }
    func testATitleIsOneLine() throws {
        let c = try start(title: "  Market\nvisit \t two ")
        XCTAssertEqual(c.manifest.title, "Market visit two")
    }
    func testNoticesAreSentencesNotErrorDumps() throws {
        audio.failNextStart = true
        let c = try start()
        guard case .couldNotRecord(let why) = try XCTUnwrap(c.notices.first) else { return XCTFail() }
        XCTAssertFalse(why.contains("Error Domain"), why); XCTAssertFalse(why.contains("("), why)
        XCTAssertFalse(why.isEmpty)
    }
}
