import XCTest
@testable import ScrivnerCore

final class ExampleSessionTests: XCTestCase {
    /// <repo>/format/examples, found from this file's own path.
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("format/examples")

    func testExampleIsConsistentAndMatchesTheCommittedCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("example-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ExampleSession.write(in: root)
        let manifest = try SessionStore.load(folder)
        XCTAssertEqual(manifest.problems(finished: true), [])
        XCTAssertEqual(manifest.spans.map(\.durationMs), [551_000, 100_000])
        XCTAssertEqual(manifest.items.count, 13)
        XCTAssertTrue(folder.url.lastPathComponent.hasPrefix("2026-11-23 1042 Market visit ["))

        let committed = Self.examples.appendingPathComponent(folder.url.lastPathComponent)
        if ProcessInfo.processInfo.environment["UPDATE_EXAMPLE"] == "1" {
            try? FileManager.default.removeItem(at: committed)
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
}
