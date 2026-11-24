import XCTest
@testable import ScrivnerCore

final class NotesMarkdownTests: XCTestCase {
    func testRenderIsExact() throws {
        var m = ManifestCodingTests.sample()
        let p = m.items[0].placement
        var later = p; later.at = p.at.adding(milliseconds: 600_000); later.utcOffset = UTCOffset(seconds: 3600)
        m.items = [
            .marker(p, type: .recordingStarted, detail: nil),
            .text(p, text: "P-014 has run the stall since 2009.", modifiedAt: nil),
            .photo(p, file: "photos/photo-0001.heic", sha256: nil, gps: nil),
            .video(p, durationMs: 48_000, endedBy: .user, sound: true, file: "video/clip-0001.mov", sha256: nil, gps: nil),
            .video(p, durationMs: nil, endedBy: nil, sound: false, file: "video/clip-0002.mov", sha256: nil, gps: nil),
            .marker(later, type: .interrupted, detail: "phone call"),
            .ink(later, endAt: nil, file: "ink/ink-0001.png", sha256: nil, data: "ink/ink-0001.drawing", dataSha256: nil, strokes: []),
        ]
        XCTAssertEqual(NotesMarkdown.render(m), """
        # Market visit

        Started 2026-11-23 10:42 (UTC+00:00, Europe/Lisbon)
        Participants: P-014

        **10:43** *Recording started*

        **10:43** P-014 has run the stall since 2009.

        **10:43** [photo: photos/photo-0001.heic]

        **10:43** [video: video/clip-0001.mov, 0:48]

        **10:43** [video: video/clip-0002.mov, no sound]

        **11:53** *Interrupted (phone call)*

        **11:53** [handwriting: ink/ink-0001.png]

        """)
    }
    func testNotesKeepOtherScriptsAndEscapeNothing() {
        var m = ManifestCodingTests.sample()
        m.title = "Рынок *утром*"; m.participants = []
        m.items = [.text(m.items[0].placement, text: "line one\nline two with \"quotes\" and 市場", modifiedAt: nil)]
        XCTAssertEqual(NotesMarkdown.render(m), "# Рынок *утром*\n\nStarted 2026-11-23 10:42 (UTC+00:00, Europe/Lisbon)\n\n**10:43** line one\nline two with \"quotes\" and 市場\n")
    }
}
