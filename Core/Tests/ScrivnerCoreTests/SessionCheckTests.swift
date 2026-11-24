import XCTest
@testable import ScrivnerCore

final class SessionCheckTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func example() throws -> SessionFolder { try ExampleSession.write(in: root) }
    func findings(_ folder: SessionFolder) -> [CheckFinding] { SessionCheck.folder(folder).findings }
    func write(_ text: String, to folder: SessionFolder, _ path: String) throws {
        try Data(text.utf8).write(to: folder.url(forRelativePath: path))
    }
    func editSessionJSON(_ folder: SessionFolder, _ edit: (String) -> String) throws {
        let text = try String(contentsOf: folder.sessionJSON, encoding: .utf8)
        let edited = edit(text)
        XCTAssertNotEqual(edited, text, "the edit changed nothing")
        try Data(edited.utf8).write(to: folder.sessionJSON)
    }

    func testTheExampleIsClean() throws {
        let result = SessionCheck.folder(try example())
        XCTAssertNotNil(result.manifest)
        XCTAssertEqual(result.findings, [])
    }
    func testMissingSessionJSON() throws {
        let folder = try example()
        try FileManager.default.removeItem(at: folder.sessionJSON)
        let result = SessionCheck.folder(folder)
        XCTAssertNil(result.manifest)
        XCTAssertEqual(result.findings, [CheckFinding(.problem, "session.json", "is missing")])
    }
    func testSessionJSONThatDoesNotDecode() throws {
        let folder = try example()
        try editSessionJSON(folder) { $0.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2") }
        let result = SessionCheck.folder(folder)
        XCTAssertNil(result.manifest)
        XCTAssertEqual(result.findings, [CheckFinding(.problem, "session.json", "version: must be 1")])
    }
    func testSessionJSONThatIsNotJSON() throws {
        let folder = try example()
        try write("{", to: folder, "session.json")
        let found = findings(folder)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.severity, .problem); XCTAssertEqual(found.first?.subject, "session.json")
        XCTAssertTrue(found.first?.message.hasPrefix("is not valid JSON") ?? false, "\(found)")
    }
    func testMissingMediaFile() throws {
        let folder = try example()
        try FileManager.default.removeItem(at: folder.url(forRelativePath: "photos/photo-0001.heic"))
        XCTAssertEqual(findings(folder), [CheckFinding(.problem, "photos/photo-0001.heic", "is listed in session.json but is not in the folder")])
    }
    func testChangedMediaFile() throws {
        let folder = try example()
        let url = folder.url(forRelativePath: "audio/audio-001.m4a")
        try (try Data(contentsOf: url) + Data([0])).write(to: url)
        XCTAssertEqual(findings(folder), [CheckFinding(.problem, "audio/audio-001.m4a",
                                                       "does not match its checksum in session.json: the file has changed or is damaged")])
    }
    func testEmptyMediaFile() throws {
        let folder = try example()
        try write("", to: folder, "video/clip-0001.mov")
        XCTAssertEqual(findings(folder), [CheckFinding(.problem, "video/clip-0001.mov", "is empty")])
    }
    func testStrayFilesAreWarnings() throws {
        let folder = try example()
        try write("x", to: folder, "extra.txt")
        try write("x", to: folder, "photos/.hidden-notes")
        let message = "is in the folder but not listed in session.json"
        XCTAssertEqual(findings(folder), [CheckFinding(.warning, "extra.txt", message),
                                          CheckFinding(.warning, "photos/.hidden-notes", message)])
    }
    func testAnUnlistedMediaFileSaysTheWorkbenchWouldTakeIt() throws {
        let folder = try example()
        try write("x", to: folder, "video/clip-0009.MOV")
        try write("x", to: folder, "photos/scan.png")
        let message = "is in the folder but not listed in session.json; the workbench would still import it"
        XCTAssertEqual(findings(folder), [CheckFinding(.warning, "photos/scan.png", message),
                                          CheckFinding(.warning, "video/clip-0009.MOV", message)])
    }
    func testTheResultSaysWhetherTheSessionIsFinished() throws {
        XCTAssertTrue(SessionCheck.folder(try example()).isFinished)
        let empty = SessionFolder(url: root.appendingPathComponent("empty"))
        XCTAssertFalse(SessionCheck.folder(empty).isFinished)
    }
    func testFoldersToCheckIncludeSessionsThatLostTheirManifest() throws {
        let good = try example()
        // An interrupted copy: the folder and its media arrived, session.json did not.
        let lost = root.appendingPathComponent("2026-11-22 0900 Lost [abcd]")
        try FileManager.default.createDirectory(at: lost.appendingPathComponent("audio"), withIntermediateDirectories: true)
        let named = root.appendingPathComponent("2026-11-21 1830 [ef01]")
        try FileManager.default.createDirectory(at: named, withIntermediateDirectories: true)
        // Not sessions: an ordinary folder, a hidden one, a file.
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Old stuff"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".Trash"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: root.appendingPathComponent("readme.txt"))

        let found = SessionCheck.sessionFolders(in: root)
        XCTAssertEqual(found.map(\.url.lastPathComponent),
                       ["2026-11-21 1830 [ef01]", "2026-11-22 0900 Lost [abcd]", good.url.lastPathComponent])
        XCTAssertEqual(SessionCheck.folder(found[1]).findings, [CheckFinding(.problem, "session.json", "is missing")])
        XCTAssertEqual(SessionCheck.sessionFolders(in: root.appendingPathComponent("Old stuff")), [])
    }
    func testWhatTheMacLeavesBehindIsIgnored() throws {
        // Finder and AirDrop leave .DS_Store files, and "._name" files beside files copied to some
        // disks. They are not part of the session, and the Mac itself hides the second kind.
        let folder = try example()
        try write("x", to: folder, ".DS_Store")
        try write("x", to: folder, "photos/.DS_Store")
        try write("x", to: folder, "photos/._photo-0001.heic")
        try write("x", to: folder, "._session.json")
        XCTAssertEqual(findings(folder), [])
    }
    func testNotesMissingOrStale() throws {
        let folder = try example()
        try write("x", to: folder, "notes.md")
        XCTAssertEqual(findings(folder), [CheckFinding(.warning, "notes.md", "is out of date with session.json")])
        try FileManager.default.removeItem(at: folder.notes)
        XCTAssertEqual(findings(folder), [CheckFinding(.warning, "notes.md", "is missing")])
    }
    func testRenamedFolder() throws {
        let folder = try example()
        let moved = SessionFolder(url: root.appendingPathComponent("Renamed"))
        try FileManager.default.moveItem(at: folder.url, to: moved.url)
        XCTAssertEqual(findings(moved), [CheckFinding(.warning, "folder",
                                                      "is named \"Renamed\"; its start time and title give \"\(folder.url.lastPathComponent)\"")])
    }
    func testUnfinishedSessionGetsOneFinding() throws {
        func moment(_ seconds: Double) -> Moment {
            Moment(host: 10 + seconds, wall: Instant(iso: "2026-11-23T04:57:10.120Z")!.adding(milliseconds: Int64(seconds * 1000)),
                   utcOffset: UTCOffset(string: "+05:45")!, timeZone: "Asia/Kathmandu")
        }
        var live = SessionTimeline(title: "Still going", participants: [], researcher: nil,
                                   device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                   startLocation: nil, at: moment(0), ids: SeededIdSource(seed: 5))
        try live.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try live.addPhoto(file: "photos/photo-0001.heic", gps: nil, at: moment(8))
        let folder = try SessionStore.create(live.manifest, in: root)
        try write("audio so far", to: folder, "audio/audio-001.m4a")
        try write("photo", to: folder, "photos/photo-0001.heic")
        let unfinished = "the session was not finished: it was still recording, was cut off, or its files have no checksums yet. Open it in the app so it can be finished."
        XCTAssertEqual(findings(folder), [CheckFinding(.problem, "session.json", unfinished)])
        XCTAssertFalse(SessionCheck.folder(folder).isFinished)

        // Stopped, but never given its checksums: still one finding, not one per file.
        try live.endRecording(by: .stop, at: moment(20))
        try SessionStore.save(live.manifest, to: folder)
        XCTAssertEqual(findings(folder), [CheckFinding(.problem, "session.json", unfinished)])

        // Finished: clean.
        _ = try SessionStore.finalize(live.manifest, in: folder)
        XCTAssertEqual(findings(folder), [])
    }
    func testInconsistentManifestIsReportedWithItsPlace() throws {
        let folder = try example()
        // The first note is moved past the end of its 9:11 span.
        try editSessionJSON(folder) { $0.replacingOccurrences(of: "\"offsetMs\": 65000", with: "\"offsetMs\": 999000") }
        try Data(NotesMarkdown.render(try SessionStore.load(folder)).utf8).write(to: folder.notes)
        XCTAssertEqual(findings(folder), [CheckFinding(.problem, "session.json", "items[1].offsetMs is past the end of its span")])
    }
    func testPathsOutsideTheFolderAreNeverOpened() throws {
        let folder = try example()
        try Data("something else entirely".utf8).write(to: root.appendingPathComponent("outside.heic"))
        try editSessionJSON(folder) { $0.replacingOccurrences(of: "\"file\": \"photos/photo-0001.heic\"", with: "\"file\": \"../outside.heic\"") }
        try Data(NotesMarkdown.render(try SessionStore.load(folder)).utf8).write(to: folder.notes)
        let found = findings(folder)
        XCTAssertTrue(found.contains(CheckFinding(.problem, "session.json", "items[2].file must be a plain relative path with no hidden or empty parts")), "\(found)")
        XCTAssertFalse(found.contains { $0.subject.contains("outside") }, "\(found)")
        // The photo it used to list is now just a file nobody lists.
        XCTAssertTrue(found.contains(CheckFinding(.warning, "photos/photo-0001.heic", "is in the folder but not listed in session.json; the workbench would still import it")))
        XCTAssertEqual(found.count, 2)
    }
}
