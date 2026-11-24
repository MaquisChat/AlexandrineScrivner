import XCTest
@testable import ScrivnerCore

final class SessionRecoveryTests: XCTestCase {
    var root: URL!
    var clock: FakeClock!
    var audio: FakeAudio!
    var location: FakeLocation!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        clock = FakeClock(); audio = FakeAudio(); location = FakeLocation()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// A session with a finished note at 20 s, a photo at 30 s and a note still being typed at 44 s,
    /// abandoned without stopping: what is left on disk when the app is killed.
    func killedMidSession() throws -> SessionFolder {
        let c = try SessionController.start(title: "Market visit", participants: [], researcher: nil,
                                            device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                            locationOn: false, in: root, clock: clock, audio: audio, location: location,
                                            ids: SeededIdSource(seed: 31))
        clock.advance(20); c.typing("a finished note"); c.finishNote()
        clock.advance(10)
        let request = c.preparePhoto()
        try Data("photo".utf8).write(to: request.url); c.photoSaved(request)
        clock.advance(14); c.typing("the last thing typed")
        c.saveIfNeeded()
        return c.folder
    }
    func reopen(_ folder: SessionFolder, audioLength: Int?) throws -> SessionController {
        clock.advance(3600)                                    // an hour later
        audio = FakeAudio()
        return try SessionController.open(folder, locationOn: false, clock: clock, audio: audio, location: location,
                                          ids: SeededIdSource(seed: 32), audioLength: { _ in audioLength })
    }

    func testReopeningAfterTheAppWasKilled() throws {
        let folder = try killedMidSession()
        let c = try reopen(folder, audioLength: 42_000)
        XCTAssertEqual(c.notices, [.recovered(dropped: [])])
        XCTAssertFalse(c.isRecording)
        XCTAssertEqual(c.manifest.spans.map(\.endedBy), [.crashRecovered])
        XCTAssertEqual(c.manifest.spans.map(\.durationMs), [42_000])
        let rows = c.page(style: .twentyFourHour).rows
        XCTAssertEqual(rows.map(\.content).suffix(2), [.text("the last thing typed", edited: false),
                                                       .marker("Interrupted (the app was closed unexpectedly) · local time, UTC+5:45")])
        let lastNote = c.manifest.items.last { $0.kind == "text" }
        XCTAssertEqual(lastNote?.placement.offsetMs, 42_000)               // typed at 44 s; the audio kept is 42 s long
        XCTAssertEqual(rows.last?.time, "10:42")                           // the marker says when it was cut off, not when it was reopened
        XCTAssertEqual(try SessionStore.load(folder), c.manifest)

        clock.advance(5); c.resume()
        XCTAssertTrue(c.isRecording)
        XCTAssertEqual(audio.started.map(\.lastPathComponent), ["audio-002.m4a"])
        clock.advance(10); c.stop()
        XCTAssertEqual(c.notices, [.recovered(dropped: [])])
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
    }
    func testReopeningWhenThePhotoNeverReachedTheDisk() throws {
        let folder = try killedMidSession()
        try FileManager.default.removeItem(at: folder.url(forRelativePath: "photos/photo-0001.heic"))
        let c = try reopen(folder, audioLength: 60_000)
        XCTAssertEqual(c.notices, [.recovered(dropped: ["photos/photo-0001.heic"])])
        XCTAssertEqual(c.manifest.items.map(\.kind), ["marker", "marker", "text", "text", "marker"])   // started, location off, two notes, interrupted
        c.stop()
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
    }
    func testReopeningWhenTheAudioCannotBeRead() throws {
        let folder = try killedMidSession()
        let c = try reopen(folder, audioLength: nil)
        XCTAssertEqual(c.manifest.spans.map(\.durationMs), [44_000])       // as long as the last thing placed on it
        c.stop()
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
    }
    func testReopeningWhenTheAudioFileItselfIsGone() throws {
        let folder = try killedMidSession()
        try FileManager.default.removeItem(at: folder.url(forRelativePath: "audio/audio-001.m4a"))
        let c = try reopen(folder, audioLength: nil)
        XCTAssertEqual(c.notices, [.recovered(dropped: ["audio/audio-001.m4a"])])
        XCTAssertEqual(c.manifest.spans, [])
        XCTAssertEqual(c.page(style: .twentyFourHour).rows.map(\.isOnAudio), [false, false, false, false, false, false])
        XCTAssertEqual(c.page(style: .twentyFourHour).rows.last?.content,
                       .marker("Interrupted (the app was closed unexpectedly) · local time, UTC+5:45"))
        clock.advance(5); c.resume(); clock.advance(5); c.stop()
        XCTAssertEqual(c.manifest.spans.map(\.file), ["audio/audio-001.m4a"])   // the name is free again
        XCTAssertEqual(SessionCheck.folder(c.folder).findings, [])
    }
    func testOpeningAFinishedSessionChangesNothing() throws {
        let c = try SessionController.start(title: "Done", participants: [], researcher: nil,
                                            device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                            locationOn: false, in: root, clock: clock, audio: audio, location: location,
                                            ids: SeededIdSource(seed: 33))
        clock.advance(10); c.stop()
        let before = try Data(contentsOf: c.folder.sessionJSON)
        let again = try reopen(c.folder, audioLength: 10_000)
        XCTAssertEqual(again.notices, [])
        XCTAssertFalse(again.isRecording)
        XCTAssertEqual(try Data(contentsOf: c.folder.sessionJSON), before)
        XCTAssertEqual(again.manifest, c.manifest)
    }
    func testOpeningAPausedSessionNeedsNoRepair() throws {
        let c = try SessionController.start(title: "Paused", participants: [], researcher: nil,
                                            device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                            locationOn: false, in: root, clock: clock, audio: audio, location: location,
                                            ids: SeededIdSource(seed: 34))
        clock.advance(10); c.pause()
        let again = try reopen(c.folder, audioLength: 10_000)             // killed while paused: nothing was open
        XCTAssertEqual(again.notices, [])
        XCTAssertEqual(again.manifest, c.manifest)
        clock.advance(5); again.resume(); clock.advance(5); again.stop()
        XCTAssertEqual(SessionCheck.folder(again.folder).findings, [])
    }
    func testOpeningAFolderThatIsNotASession() throws {
        let empty = SessionFolder(url: root.appendingPathComponent("Not a session"))
        try FileManager.default.createDirectory(at: empty.url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try reopen(empty, audioLength: nil)) {
            XCTAssertEqual($0 as? SessionControllerError, .notASession("Not a session"))
        }
        try Data("{".utf8).write(to: empty.sessionJSON)
        XCTAssertThrowsError(try reopen(empty, audioLength: nil))
    }
}
