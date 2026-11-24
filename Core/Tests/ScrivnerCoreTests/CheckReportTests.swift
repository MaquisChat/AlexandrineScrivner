import XCTest
@testable import ScrivnerCore

final class CheckReportTests: XCTestCase {
    func testCleanReport() {
        XCTAssertEqual(CheckReport.render(folderName: "S", findings: [], media: .checked), "Session: S\n  Nothing wrong.\n")
        XCTAssertEqual(CheckReport.render(folderName: "S", findings: [], media: .notAsked),
                       "Session: S\n  Nothing wrong.\n  Media tags were not checked. Run again with --media to check them.\n")
        let unfinished = [CheckFinding(.problem, "session.json", "the session was not finished")]
        XCTAssertEqual(CheckReport.render(folderName: "S", findings: unfinished, media: .skippedUnfinished),
                       "Session: S\n  PROBLEM  session.json: the session was not finished\n  Media tags were not checked, because the session is not finished.\n")
        XCTAssertEqual(CheckReport.render(folderName: "S", findings: unfinished, media: .failed), "Session: S\n  PROBLEM  session.json: the session was not finished\n")
    }
    func testMixedReport() {
        let findings = [
            CheckFinding(.warning, "notes.md", "is out of date with session.json"),
            CheckFinding(.problem, "photos/photo-0001.heic", "says it was taken at 10:45:17 but session.json says 10:45:15"),
            CheckFinding(.problem, "media tags", "could not be checked: ExifTool was not found"),
        ]
        XCTAssertEqual(CheckReport.render(folderName: "2026-11-23 1042 Market visit [1a2b]", findings: findings, media: .notAsked), """
        Session: 2026-11-23 1042 Market visit [1a2b]
          PROBLEM  photos/photo-0001.heic: says it was taken at 10:45:17 but session.json says 10:45:15
          PROBLEM  media tags: could not be checked: ExifTool was not found
          warning  notes.md: is out of date with session.json
          Media tags were not checked. Run again with --media to check them.

        """)
    }
    func testVerdicts() {
        XCTAssertEqual(CheckReport.verdict(sessions: 1, problems: 0, warnings: 2), "SESSION CHECK OK (1 session, 0 problems, 2 warnings)")
        XCTAssertEqual(CheckReport.verdict(sessions: 2, problems: 3, warnings: 1), "SESSION CHECK FAILED (2 sessions, 3 problems, 1 warning)")
        XCTAssertEqual(CheckReport.verdict(sessions: 1, problems: 1, warnings: 0), "SESSION CHECK FAILED (1 session, 1 problem, 0 warnings)")
        XCTAssertEqual(CheckReport.verdict(sessions: 0, problems: 0, warnings: 0), "SESSION CHECK FAILED (0 sessions, 0 problems, 0 warnings)")
    }
    func testArguments() {
        XCTAssertEqual(CheckArguments(["a"]), CheckArguments(folders: ["a"], media: false, exiftool: nil))
        XCTAssertEqual(CheckArguments(["--media", "--exiftool", "/x/exiftool", "a", "b"]),
                       CheckArguments(folders: ["a", "b"], media: true, exiftool: "/x/exiftool"))
        XCTAssertEqual(CheckArguments(["a", "--media"]), CheckArguments(folders: ["a"], media: true, exiftool: nil))
        XCTAssertNil(CheckArguments([]))
        XCTAssertNil(CheckArguments(["--media"]))
        XCTAssertNil(CheckArguments(["--bogus", "a"]))
        XCTAssertNil(CheckArguments(["a", "--exiftool"]))
        XCTAssertTrue(CheckArguments.usage.contains("scrivner-check [--media] [--exiftool PATH] FOLDER..."))
    }
    func testMediaPathsAreTheTidyListedPhotosClipsAndAudio() throws {
        var manifest = SchemaSamplesTests.allKinds()
        XCTAssertEqual(MediaCheck.mediaPaths(in: manifest),
                       ["audio/audio-001.m4a", "audio/audio-002.m4a", "photos/photo-0001.heic", "video/clip-0001.mov", "video/clip-0002.mov"])
        manifest.spans[0].file = "../outside.m4a"
        XCTAssertEqual(MediaCheck.mediaPaths(in: manifest).first, "audio/audio-002.m4a")
    }
}
