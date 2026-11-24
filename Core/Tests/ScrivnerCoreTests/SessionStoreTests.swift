import XCTest
@testable import ScrivnerCore

final class SessionStoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func closed() -> Manifest {
        var m = ManifestCodingTests.sample()
        m.spans[0].durationMs = 551_000; m.spans[0].endedBy = .stop
        return m
    }

    func testCreateSaveLoad() throws {
        let m = closed()
        let folder = try SessionStore.create(m, in: root)
        XCTAssertEqual(folder.url.lastPathComponent, "2026-11-23 1042 Market visit [0000]")
        for sub in ["audio", "photos", "video", "ink"] {
            var isDir: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent(sub).path, isDirectory: &isDir) && isDir.boolValue, sub)
        }
        XCTAssertEqual(try String(contentsOf: folder.sessionJSON, encoding: .utf8), ManifestCoding.encode(m))
        XCTAssertEqual(try String(contentsOf: folder.notes, encoding: .utf8), NotesMarkdown.render(m))
        XCTAssertEqual(try SessionStore.load(folder), m)
        XCTAssertThrowsError(try SessionStore.create(m, in: root)) {
            XCTAssertEqual($0 as? SessionStoreError, .folderExists("2026-11-23 1042 Market visit [0000]"))
        }
        XCTAssertEqual(SessionStore.sessions(in: root).map(\.url.lastPathComponent), [folder.url.lastPathComponent])
    }
    func testNextFileCountsWhatIsListed() {
        var m = closed()
        XCTAssertEqual(SessionStore.nextFile(.audio, ext: "m4a", in: m), "audio/audio-002.m4a")
        XCTAssertEqual(SessionStore.nextFile(.photo, ext: "heic", in: m), "photos/photo-0001.heic")
        m.items.append(.photo(m.items[0].placement, file: "photos/photo-0001.heic", sha256: nil, gps: nil))
        m.items.append(.ink(m.items[0].placement, endAt: nil, file: "ink/ink-0001.png", sha256: nil, data: "ink/ink-0001.drawing", dataSha256: nil, strokes: []))
        XCTAssertEqual(SessionStore.nextFile(.photo, ext: "heic", in: m), "photos/photo-0002.heic")
        XCTAssertEqual(SessionStore.nextFile(.video, ext: "mov", in: m), "video/clip-0001.mov")
        XCTAssertEqual(SessionStore.nextFile(.inkPicture, ext: "png", in: m), "ink/ink-0002.png")
        XCTAssertEqual(SessionStore.nextFile(.inkData, ext: "drawing", in: m), "ink/ink-0002.drawing")
    }
    func testFinalizeHashesFilesAndRefusesGaps() throws {
        var m = closed()
        var photo = m.items[0].placement; photo.id = "00000000-0000-7000-8000-000000000003"
        m.items.append(.photo(photo, file: "photos/photo-0001.heic", sha256: nil, gps: nil))
        let folder = try SessionStore.create(m, in: root)
        XCTAssertThrowsError(try SessionStore.finalize(m, in: folder)) {
            XCTAssertEqual($0 as? SessionStoreError, .missingFile("audio/audio-001.m4a"))
        }
        try Data("audio".utf8).write(to: folder.url(forRelativePath: "audio/audio-001.m4a"))
        try Data("photo".utf8).write(to: folder.url(forRelativePath: "photos/photo-0001.heic"))
        let done = try SessionStore.finalize(m, in: folder)
        XCTAssertEqual(done.spans[0].sha256, SHA256Hex.of(Data("audio".utf8)))
        guard case .photo(_, _, let hash, _) = done.items[1] else { return XCTFail() }
        XCTAssertEqual(hash, SHA256Hex.of(Data("photo".utf8)))
        XCTAssertEqual(try SessionStore.load(folder), done)
        XCTAssertEqual(done.problems(finished: true), [])

        var open = m; open.spans[0].durationMs = nil; open.spans[0].endedBy = nil
        XCTAssertThrowsError(try SessionStore.finalize(open, in: folder)) {
            guard case .inconsistent(let problems)? = $0 as? SessionStoreError else { return XCTFail() }
            XCTAssertEqual(problems.map(\.path), ["spans[0].endedBy"])
        }
    }
    func testRenameToMatchTitle() throws {
        var m = closed()
        let folder = try SessionStore.create(m, in: root)
        XCTAssertEqual(try SessionStore.renameToMatchTitle(folder, manifest: m), folder)
        m.title = "Fish stall: second visit"
        let renamed = try SessionStore.renameToMatchTitle(folder, manifest: m)
        XCTAssertEqual(renamed.url.lastPathComponent, "2026-11-23 1042 Fish stall- second visit [0000]")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.sessionJSON.path))
    }
}
