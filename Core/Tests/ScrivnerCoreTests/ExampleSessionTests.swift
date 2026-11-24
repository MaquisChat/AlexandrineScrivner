import XCTest
@testable import ScrivnerCore

final class ExampleSessionTests: XCTestCase {
    /// The example folder kept in the repository, if there is one yet.
    static func committedExample() -> URL? {
        SessionStore.sessions(in: examples).first?.url
    }

    /// <repo>/format/examples, found from this file's own path.
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("format/examples")

    func testExampleIsConsistentAndMatchesTheCommittedCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("example-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        // The example's media are real files kept in the repository; the code writes everything else.
        let folder = try ExampleSession.write(in: root, mediaFrom: Self.committedExample())
        let manifest = try SessionStore.load(folder)
        XCTAssertEqual(manifest.problems(finished: true), [])
        XCTAssertEqual(manifest.createdAt.iso, "2026-11-23T04:57:10.120Z")
        XCTAssertEqual(manifest.utcOffset.string, "+05:45")     // a clock that is not UTC, on purpose
        XCTAssertEqual(manifest.timeZone, "Asia/Kathmandu")
        XCTAssertEqual(manifest.spans.map(\.durationMs), [551_000, 100_000])
        XCTAssertEqual(manifest.items.count, 13)
        XCTAssertTrue(folder.url.lastPathComponent.hasPrefix("2026-11-23 1042 Market visit ["))

        let committed = Self.examples.appendingPathComponent(folder.url.lastPathComponent)
        if ProcessInfo.processInfo.environment["UPDATE_EXAMPLE"] == "1" {
            // Only one example is kept; an older one under another name goes.
            for old in (try? FileManager.default.contentsOfDirectory(at: Self.examples, includingPropertiesForKeys: nil)) ?? [] {
                try FileManager.default.removeItem(at: old)
            }
            try FileManager.default.createDirectory(at: Self.examples, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: folder.url, to: committed)
        }
        var files: [String] = ["session.json", "notes.md"]
        files += manifest.spans.map(\.file)
        for item in manifest.items {
            switch item {
            case .photo(_, let file, _, _): files.append(file)
            case .video(_, _, _, _, let file, _, _): files.append(file)
            default: break
            }
        }
        for file in files {
            XCTAssertEqual(try? Data(contentsOf: committed.appendingPathComponent(file)),
                           try Data(contentsOf: folder.url.appendingPathComponent(file)),
                           "format/examples is out of date for \(file): run the tests once with UPDATE_EXAMPLE=1")
        }
    }

    func testCommittedExamplePassesTheFolderCheck() throws {
        let folders = SessionStore.sessions(in: Self.examples)
        XCTAssertEqual(folders.count, 1)
        let result = SessionCheck.folder(try XCTUnwrap(folders.first))
        XCTAssertEqual(result.findings, [])
        // Real media, not placeholders: every listed file is bigger than a one-line text file.
        for file in SessionCheck.listedFiles(in: try XCTUnwrap(result.manifest)) {
            let attributes = try FileManager.default.attributesOfItem(atPath: folders[0].url(forRelativePath: file.path).path)
            XCTAssertGreaterThan((attributes[.size] as? NSNumber)?.intValue ?? 0, 500, file.path)
        }
    }
}
