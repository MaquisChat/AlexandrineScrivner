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
    func testSaveRefusesAManifestItCouldNotReadBack() throws {
        let good = closed()
        let folder = try SessionStore.create(good, in: root)
        var bad = good; bad.startLocation = GeoPoint(lat: 38.7, lon: -9.1, alt: .nan, accuracyM: nil)
        XCTAssertThrowsError(try SessionStore.save(bad, to: folder)) {
            guard case .unwritable(let why)? = $0 as? SessionStoreError else { return XCTFail("\($0)") }
            XCTAssertTrue(why.hasPrefix("startLocation.alt"), why)
        }
        XCTAssertEqual(try SessionStore.load(folder), good)        // the last good copy is still there
        var skewed = good; skewed.utcOffset = UTCOffset(seconds: 100_000)
        XCTAssertThrowsError(try SessionStore.save(skewed, to: folder))
        XCTAssertEqual(try SessionStore.load(folder), good)
    }
    func testCrashedSessionCanBeRecoveredAndFinished() throws {
        func moment(_ seconds: Double) -> Moment {
            Moment(host: 10 + seconds, wall: ManifestCodingTests.t0.adding(milliseconds: Int64(seconds * 1000)),
                   utcOffset: ManifestCodingTests.zero, timeZone: "Europe/Lisbon")
        }
        // Recording, a photo that was saved, a note 44 s in, and a clip whose file never reached the disk.
        var live = SessionTimeline(title: "Market visit", participants: [], researcher: nil,
                                   device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                   startLocation: nil, at: moment(0), ids: SeededIdSource(seed: 7))
        try live.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try live.addPhoto(file: "photos/photo-0001.heic", gps: nil, at: moment(20))
        try live.addText("the last thing typed", at: moment(44))
        try live.startClip(file: "video/clip-0001.mov", gps: nil, at: moment(45))
        let folder = try SessionStore.create(live.manifest, in: root)
        try Data("audio".utf8).write(to: folder.url(forRelativePath: "audio/audio-001.m4a"))
        try Data("photo".utf8).write(to: folder.url(forRelativePath: "photos/photo-0001.heic"))

        // The app is killed here. On the next launch:
        let repaired = SessionStore.droppingMissingFiles(from: try SessionStore.load(folder), in: folder)
        XCTAssertEqual(repaired.dropped, ["video/clip-0001.mov"])
        var back = SessionTimeline(resuming: repaired.manifest, ids: SeededIdSource(seed: 8))
        XCTAssertTrue(back.needsRecovery)
        try back.recoverAfterCrash(spanDurationMs: 42_000, at: moment(500))
        let done = try SessionStore.finalize(back.manifest, in: folder)
        XCTAssertEqual(done.problems(finished: true), [])
        XCTAssertEqual(done.items.map(\.kind), ["marker", "photo", "text", "marker"])
        XCTAssertEqual(done.items.map(\.placement.offsetMs), [0, 20_000, 42_000, nil])
        XCTAssertEqual(try SessionStore.load(folder), done)
    }
    func testDroppingAMissingAudioFileUnplacesItsItems() throws {
        var m = closed()
        var inkPlace = m.items[0].placement; inkPlace.id = "00000000-0000-7000-8000-000000000003"
        m.items.append(.ink(inkPlace, endAt: nil, file: "ink/ink-0001.png", sha256: nil, data: "ink/ink-0001.drawing", dataSha256: nil,
                            strokes: [InkStroke(at: inkPlace.at, spanId: m.spans[0].id, offsetMs: 65_000, bounds: [0, 0, 1, 1])]))
        let folder = try SessionStore.create(m, in: root)
        try Data("ink".utf8).write(to: folder.url(forRelativePath: "ink/ink-0001.png"))
        try Data("ink".utf8).write(to: folder.url(forRelativePath: "ink/ink-0001.drawing"))

        let repaired = SessionStore.droppingMissingFiles(from: m, in: folder)
        XCTAssertEqual(repaired.dropped, ["audio/audio-001.m4a"])
        XCTAssertEqual(repaired.manifest.spans, [])
        XCTAssertEqual(repaired.manifest.items.map(\.placement.spanId), [nil, nil])
        XCTAssertEqual(repaired.manifest.items.map(\.placement.offsetMs), [nil, nil])
        XCTAssertEqual(repaired.manifest.items[0].placement.at, m.items[0].placement.at)
        guard case .ink(_, _, _, _, _, _, let strokes) = repaired.manifest.items[1] else { return XCTFail() }
        XCTAssertNil(strokes[0].spanId); XCTAssertNil(strokes[0].offsetMs)
        XCTAssertEqual(repaired.manifest.problems(finished: false), [])

        // A handwriting block goes when either of its two files is missing. Nothing missing: nothing changes.
        try Data("audio".utf8).write(to: folder.url(forRelativePath: "audio/audio-001.m4a"))
        XCTAssertEqual(SessionStore.droppingMissingFiles(from: m, in: folder).dropped, [])
        XCTAssertEqual(SessionStore.droppingMissingFiles(from: m, in: folder).manifest, m)
        try FileManager.default.removeItem(at: folder.url(forRelativePath: "ink/ink-0001.drawing"))
        let withoutInk = SessionStore.droppingMissingFiles(from: m, in: folder)
        XCTAssertEqual(withoutInk.dropped, ["ink/ink-0001.drawing"])
        XCTAssertEqual(withoutInk.manifest.items.map(\.kind), ["text"])
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
