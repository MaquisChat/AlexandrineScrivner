import XCTest
@testable import ScrivnerCore

final class SessionListTests: XCTestCase {
    var root: URL!
    var clock: FakeClock!
    var audio: FakeAudio!
    let location = FakeLocation()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("list-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        clock = FakeClock(); audio = FakeAudio()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func start(_ title: String, seed: UInt64) throws -> SessionController {
        try SessionController.start(title: title, participants: [], researcher: nil,
                                    device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                    locationOn: false, in: root, clock: clock, audio: audio, location: location,
                                    ids: SeededIdSource(seed: seed))
    }
    func snap(_ c: SessionController) throws {
        let request = c.preparePhoto()
        try Data("photo".utf8).write(to: request.url); c.photoSaved(request)
    }

    func testListIsNewestFirstWithCounts() throws {
        let first = try start("Morning", seed: 1)
        clock.advance(10); try snap(first); try snap(first)
        clock.advance(10); audio.lengthOnStop = 20_000; first.stop()
        clock.advance(3600)
        let second = try start("Afternoon", seed: 2)
        clock.advance(30); audio.lengthOnStop = 30_000; second.pause()
        clock.advance(5); second.resume(); clock.advance(15); audio.lengthOnStop = 15_000; second.stop()
        clock.advance(3600)
        let third = try start("Still going", seed: 3)
        clock.advance(5); try snap(third)

        let list = SessionSummary.list(in: root, exports: ExportRecord())
        XCTAssertEqual(list.unreadable, [])
        XCTAssertEqual(list.sessions.map(\.title), ["Still going", "Afternoon", "Morning"])
        XCTAssertEqual(list.sessions.map(\.recordedMilliseconds), [0, 45_000, 20_000])
        XCTAssertEqual(list.sessions.map(\.photoCount), [1, 0, 2])
        XCTAssertEqual(list.sessions.map(\.clipCount), [0, 0, 0])
        XCTAssertEqual(list.sessions.map(\.isFinished), [false, true, true])
        XCTAssertEqual(list.sessions.map(\.export), [.never, .never, .never])
        XCTAssertEqual(list.sessions.map(\.id), [third.manifest.id, second.manifest.id, first.manifest.id])
        XCTAssertEqual(list.sessions[2].folder, first.folder)
        XCTAssertEqual(list.sessions[2].startedAt, first.manifest.createdAt)
        XCTAssertEqual(SessionSummary.list(in: root.appendingPathComponent("nowhere"), exports: ExportRecord()).sessions, [])
    }
    func testAnUntitledSessionIsListedByItsDateAndTime() throws {
        _ = try start("", seed: 4)
        XCTAssertEqual(SessionSummary.list(in: root, exports: ExportRecord()).sessions.map(\.title), ["2026-11-23 10:42"])
    }
    func testAnUnreadableFolderIsReportedNotDropped() throws {
        let good = try start("Good", seed: 5)
        clock.advance(5); good.stop()
        let broken = root.appendingPathComponent("2026-11-22 0900 Broken [abcd]")
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: broken.appendingPathComponent("session.json"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Just a folder"), withIntermediateDirectories: true)
        let list = SessionSummary.list(in: root, exports: ExportRecord())
        XCTAssertEqual(list.sessions.map(\.title), ["Good"])
        XCTAssertEqual(list.unreadable, ["2026-11-22 0900 Broken [abcd]"])
    }
    func testExportStates() throws {
        let c = try start("Shared", seed: 6)
        clock.advance(10); c.stop()
        var record = ExportRecord()
        func state() throws -> ExportState {
            try XCTUnwrap(SessionSummary.list(in: root, exports: record).sessions.first).export
        }
        XCTAssertEqual(try state(), .never)
        let firstExport = clock.now().wall
        record.noteExport(of: c.manifest, sessionJSON: try Data(contentsOf: c.folder.sessionJSON), at: firstExport)
        XCTAssertEqual(try state(), .exported(firstExport))
        clock.advance(60); c.typing("added afterwards"); c.finishNote()
        XCTAssertEqual(try state(), .changedSince(firstExport))
        clock.advance(60)
        let secondExport = clock.now().wall
        record.noteExport(of: c.manifest, sessionJSON: try Data(contentsOf: c.folder.sessionJSON), at: secondExport)
        XCTAssertEqual(try state(), .exported(secondExport))
    }
    func testExportRecordSurvivesSavingAndLoading() throws {
        let c = try start("Shared", seed: 7)
        clock.advance(10); c.stop()
        var record = ExportRecord()
        record.noteExport(of: c.manifest, sessionJSON: try Data(contentsOf: c.folder.sessionJSON), at: clock.now().wall)
        let file = root.appendingPathComponent("exports.json")
        try record.save(to: file)
        XCTAssertEqual(ExportRecord.load(from: file), record)
        XCTAssertNotEqual(record, ExportRecord())
        XCTAssertEqual(ExportRecord.load(from: root.appendingPathComponent("missing.json")), ExportRecord())
        try Data("rubbish".utf8).write(to: file)
        XCTAssertEqual(ExportRecord.load(from: file), ExportRecord())
        try Data(#"{"version": 1, "exports": {"x": {"at": "not a time", "sha256": "zz"}}}"#.utf8).write(to: file)
        XCTAssertEqual(ExportRecord.load(from: file), ExportRecord())
    }
    func testDeletingASession() throws {
        let c = try start("To delete", seed: 8)
        clock.advance(10); c.stop()
        var record = ExportRecord()
        record.noteExport(of: c.manifest, sessionJSON: try Data(contentsOf: c.folder.sessionJSON), at: clock.now().wall)

        let notASession = SessionFolder(url: root.appendingPathComponent("Holiday photos"))
        try FileManager.default.createDirectory(at: notASession.url, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: notASession.url.appendingPathComponent("keep.txt"))
        XCTAssertThrowsError(try SessionStore.delete(notASession))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notASession.url.appendingPathComponent("keep.txt").path))

        try SessionStore.delete(c.folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: c.folder.url.path))
        XCTAssertEqual(SessionSummary.list(in: root, exports: record).sessions, [])
        record.forget(sessionId: c.manifest.id)
        XCTAssertEqual(record, ExportRecord())
    }
}
