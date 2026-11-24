import XCTest
@testable import ScrivnerCore

final class MediaCheckTests: XCTestCase {
    let offset = UTCOffset(string: "+05:45")!
    let t0 = Instant(iso: "2026-11-23T04:57:10.120Z")!     // 10:42:10 on the local clock
    let place = GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: 5)
    let audioFile = "audio/audio-001.m4a", photoFile = "photos/photo-0001.heic", clipFile = "video/clip-0001.mov"

    func moment(_ seconds: Double) -> Moment {
        Moment(host: 100 + seconds, wall: t0.adding(milliseconds: Int64(seconds * 1000)), utcOffset: offset, timeZone: "Asia/Kathmandu")
    }
    /// One span of 60 s; a photo with a location at 10 s; a clip with no location from 20 s to 30 s.
    func manifest() throws -> Manifest {
        var t = SessionTimeline(title: "Check", participants: [], researcher: nil,
                                device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                startLocation: place, at: moment(0), ids: SeededIdSource(seed: 3))
        try t.startRecording(file: audioFile, at: moment(0))
        try t.addPhoto(file: photoFile, gps: place, at: moment(10))
        let clip = try t.startClip(file: clipFile, gps: nil, at: moment(20))
        try t.endClip(id: clip, by: .user, at: moment(30))
        try t.endRecording(by: .stop, at: moment(60))
        return t.manifest
    }
    /// What ExifTool would report for files that agree with `manifest()`.
    func agreeing() -> [String: MediaFacts] {
        var audio = MediaFacts()
        audio.created = ExifDate("2026:11:23 04:57:10+00:00")
        audio.creationDate = ExifDate("2026:11:23 10:42:10+05:45")
        audio.make = "Apple"; audio.model = "iPhone 17 Pro"; audio.durationMs = 60_000
        var photo = MediaFacts()
        photo.original = ExifDate("2026:11:23 10:42:20.120+05:45")
        photo.location = GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: nil)
        photo.make = "Apple"; photo.model = "iPhone 17 Pro"; photo.lens = "iPhone 17 Pro back camera 6.765mm f/1.78"
        var clip = MediaFacts()
        clip.created = ExifDate("2026:11:23 04:57:30+00:00")
        clip.creationDate = ExifDate("2026:11:23 10:42:30+05:45")
        clip.make = "Apple"; clip.model = "iPhone 17 Pro"; clip.durationMs = 10_000
        return [audioFile: audio, photoFile: photo, clipFile: clip]
    }
    func check(_ edit: (inout [String: MediaFacts]) -> Void = { _ in }) throws -> [CheckFinding] {
        var facts = agreeing()
        edit(&facts)
        return MediaCheck.findings(for: try manifest(), facts: facts)
    }
    func problems(_ findings: [CheckFinding]) -> [CheckFinding] { findings.filter { $0.severity == .problem } }
    func warnings(_ findings: [CheckFinding]) -> [CheckFinding] { findings.filter { $0.severity == .warning } }
    /// Exactly one finding, of the given kind, about the given file; returns its message.
    func only(_ findings: [CheckFinding], _ severity: CheckFinding.Severity, _ subject: String,
              file: StaticString = #filePath, line: UInt = #line) -> String {
        XCTAssertEqual(findings.count, 1, "\(findings)", file: file, line: line)
        XCTAssertEqual(findings.first?.severity, severity, file: file, line: line)
        XCTAssertEqual(findings.first?.subject, subject, file: file, line: line)
        return findings.first?.message ?? ""
    }

    func testAgreeingFilesGiveNoFindings() throws {
        XCTAssertEqual(try check(), [])
    }
    func testUnreadableFile() throws {
        let f = try check { $0[self.photoFile]?.error = "File format error"; $0[self.photoFile]?.original = nil }
        XCTAssertEqual(only(f, .problem, photoFile), "could not be read: File format error")
    }
    func testMissingFacts() throws {
        let f = try check { $0[self.clipFile] = nil }
        XCTAssertEqual(only(f, .problem, clipFile), "could not be read: ExifTool returned nothing for it")
    }
    func testPhotoTimeOffByTwoSeconds() throws {
        let f = try check { $0[self.photoFile]?.original = ExifDate("2026:11:23 10:42:22.120+05:45") }
        XCTAssertEqual(only(f, .problem, photoFile), "says it was taken at 10:42:22 but session.json says 10:42:20")
    }
    func testPhotoTimeOffByNineHundredMillisecondsIsFine() throws {
        XCTAssertEqual(try check { $0[self.photoFile]?.original = ExifDate("2026:11:23 10:42:21.020+05:45") }, [])
    }
    func testPhotoWithoutCaptureTime() throws {
        let f = try check { $0[self.photoFile]?.original = nil }
        XCTAssertEqual(only(f, .problem, photoFile), "has no capture time inside it (EXIF DateTimeOriginal)")
    }
    func testPhotoWithoutOffset() throws {
        let f = try check { $0[self.photoFile]?.original = ExifDate("2026:11:23 10:42:20.120") }
        XCTAssertEqual(only(f, .problem, photoFile), "has no time zone offset inside it (EXIF OffsetTimeOriginal)")
    }
    func testPhotoWithWrongOffset() throws {
        // The same moment, written as if the phone were on UTC+05:30.
        let f = try check { $0[self.photoFile]?.original = ExifDate("2026:11:23 10:27:20.120+05:30") }
        XCTAssertEqual(only(f, .problem, photoFile), "says its offset from UTC is +05:30 but session.json says +05:45")
    }
    func testPhotoWithoutSubSecondsOrLens() throws {
        let f = try check { $0[self.photoFile]?.original = ExifDate("2026:11:23 10:42:20+05:45"); $0[self.photoFile]?.lens = nil }
        XCTAssertEqual(problems(f), [])
        XCTAssertEqual(warnings(f).map(\.message), ["capture time has no sub-seconds", "does not name the lens"])
        XCTAssertEqual(Set(f.map(\.subject)), [photoFile])
    }
    func testClipWithoutCreationTimes() throws {
        let noApple = try check { $0[self.clipFile]?.creationDate = nil }
        XCTAssertEqual(only(noApple, .problem, clipFile), "has no creation date with the local offset inside it (Apple creation date)")
        let noQuickTime = try check { $0[self.clipFile]?.created = nil }
        XCTAssertEqual(only(noQuickTime, .problem, clipFile), "has no creation time inside it (QuickTime CreateDate)")
    }
    func testClipMadeAtAnotherTimeOrOffset() throws {
        let late = try check { $0[self.clipFile]?.created = ExifDate("2026:11:23 04:58:30+00:00") }
        XCTAssertEqual(only(late, .problem, clipFile), "says it was made at 10:43:30 but session.json says 10:42:30")
        let appleLate = try check { $0[self.clipFile]?.creationDate = ExifDate("2026:11:23 10:43:30+05:45") }
        XCTAssertEqual(only(appleLate, .problem, clipFile), "says it was made at 10:43:30 (Apple creation date) but session.json says 10:42:30")
        let otherZone = try check { $0[self.clipFile]?.creationDate = ExifDate("2026:11:23 04:57:30+00:00") }
        XCTAssertEqual(only(otherZone, .problem, clipFile), "says its offset from UTC is +00:00 but session.json says +05:45")
    }
    func testClipDurationDiffers() throws {
        let f = try check { $0[self.clipFile]?.durationMs = 8_000 }
        XCTAssertEqual(only(f, .warning, clipFile), "is 0:08 long but session.json says 0:10")
        XCTAssertEqual(try check { $0[self.clipFile]?.durationMs = 9_100 }, [])
    }
    func testLocationMissingFromFile() throws {
        let f = try check { $0[self.photoFile]?.location = nil }
        XCTAssertEqual(only(f, .problem, photoFile), "has no location inside it although session.json gives one")
    }
    func testLocationDiffers() throws {
        let f = try check { $0[self.photoFile]?.location?.lat += 0.001 }
        XCTAssertEqual(only(f, .problem, photoFile), "says it was made at 27.70560, 85.30760 but session.json says 27.70460, 85.30760")
        XCTAssertEqual(try check { $0[self.photoFile]?.location?.lat += 0.00005 }, [])
        let high = try check { $0[self.photoFile]?.location?.alt = 1350 }
        XCTAssertEqual(only(high, .problem, photoFile), "says its altitude is 1350 m but session.json says 1300 m")
        XCTAssertEqual(try check { $0[self.photoFile]?.location?.alt = nil }, [])
    }
    func testLocationInsideAFileThatShouldHaveNone() throws {
        let f = try check { $0[self.clipFile]?.location = GeoPoint(lat: 27.7046, lon: 85.3076, alt: nil, accuracyM: nil) }
        XCTAssertEqual(only(f, .problem, clipFile), "carries a location although session.json has none for it")
    }
    func testAudioWithLocation() throws {
        let f = try check { $0[self.audioFile]?.location = GeoPoint(lat: 27.7046, lon: 85.3076, alt: nil, accuracyM: nil) }
        XCTAssertEqual(only(f, .problem, audioFile), "carries a location; audio is never located")
    }
    func testAudioShorterThanAnItemsPosition() throws {
        let f = try check { $0[self.audioFile]?.durationMs = 15_000 }
        XCTAssertEqual(Set(f.map(\.subject)), [audioFile])
        XCTAssertEqual(problems(f).map(\.message), ["is 0:15 long, but an item in session.json sits at 1:00 on it"])
        XCTAssertEqual(warnings(f).map(\.message), ["is 0:15 long but session.json says 1:00"])
    }
    func testLivePhotoIdentifier() throws {
        // On its own it does nothing in the workbench, which only joins a photo and a clip that share one.
        let lone = try check { $0[self.photoFile]?.contentIdentifier = "5B3B3A0E" }
        XCTAssertEqual(only(lone, .warning, photoFile), "carries a Live Photo identifier")
        let shared = try check { $0[self.photoFile]?.contentIdentifier = "5B3B3A0E"; $0[self.clipFile]?.contentIdentifier = "5B3B3A0E" }
        XCTAssertEqual(shared, [
            CheckFinding(.problem, photoFile, "shares a Live Photo identifier with video/clip-0001.mov, so the workbench would join them into one item"),
            CheckFinding(.problem, clipFile, "shares a Live Photo identifier with photos/photo-0001.heic, so the workbench would join them into one item"),
        ])
    }
    func testAPlaceTuckedAwayElsewhereInAFile() throws {
        let clip = try check { $0[self.clipFile]?.strayLocationTags = ["UserData:GPSCoordinates"] }
        XCTAssertEqual(only(clip, .problem, clipFile), "carries a location although session.json has none for it (found in UserData:GPSCoordinates)")
        let audio = try check { $0[self.audioFile]?.strayLocationTags = ["ItemList:GPSCoordinates"] }
        XCTAssertEqual(only(audio, .problem, audioFile), "carries a location; audio is never located (found in ItemList:GPSCoordinates)")
        // A photo that should have a place, has it in the right spot, and has another copy elsewhere.
        let photo = try check { $0[self.photoFile]?.strayLocationTags = ["XMP-exif:GPSLatitude", "XMP-exif:GPSLongitude"] }
        XCTAssertEqual(only(photo, .warning, photoFile), "also carries a location in XMP-exif:GPSLatitude, XMP-exif:GPSLongitude, which the workbench may read instead")
        // A place that is there but in none of the right spots does not count as the place session.json gives.
        let misplaced = try check { $0[self.photoFile]?.location = nil; $0[self.photoFile]?.strayLocationTags = ["XMP-exif:GPSLatitude"] }
        XCTAssertEqual(problems(misplaced).map(\.message), ["has no location inside it although session.json gives one"])
        XCTAssertEqual(warnings(misplaced).count, 1)
    }
    func testADateThatIsWrongByADay() throws {
        // The same clock time on the wrong day: the report has to show the dates, or the two times look identical.
        let photo = try check { $0[self.photoFile]?.original = ExifDate("2026:11:24 10:42:20.120+05:45") }
        XCTAssertEqual(only(photo, .problem, photoFile), "says it was taken at 2026-11-24 10:42:20 but session.json says 2026-11-23 10:42:20")
        let clip = try check { $0[self.clipFile]?.created = ExifDate("2026:11:22 04:57:30+00:00") }
        XCTAssertEqual(only(clip, .problem, clipFile), "says it was made at 2026-11-22 10:42:30 but session.json says 2026-11-23 10:42:30")
    }
    func testFilesWhosePathsAreNotTidyAreLeftToTheFolderCheck() throws {
        var m = try manifest()
        var p = m.items[1].placement; p.id = "00000000-0000-7000-8000-00000000000a"
        m.items.append(.photo(p, file: "../outside.heic", sha256: nil, gps: nil))
        XCTAssertEqual(MediaCheck.findings(for: m, facts: agreeing()), [])
    }
    func testNoMakeOrModel() throws {
        let f = try check { $0[self.clipFile]?.make = nil; $0[self.clipFile]?.model = nil }
        XCTAssertEqual(only(f, .warning, clipFile), "does not name the device that made it (make and model)")
        XCTAssertEqual(try check { $0[self.clipFile]?.make = nil }, [])
    }
}
