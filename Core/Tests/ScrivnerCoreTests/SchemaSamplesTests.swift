import XCTest
@testable import ScrivnerCore

/// Keeps the Swift reader and writer in step with the schema in `format/`:
/// `format/valid` holds manifests exactly as Swift writes them, which the schema check must accept;
/// `format/invalid` holds the samples the schema rejects, which Swift must reject too.
final class SchemaSamplesTests: XCTestCase {
    /// <repo>/format, found from this file's own path.
    static let format = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("format")

    static func id(_ n: Int) -> String {
        let hex = String(n, radix: 16)
        return "00000000-0000-7000-8000-" + String(repeating: "0", count: 12 - hex.count) + hex
    }

    /// A finished session that uses every key the format has.
    static func allKinds() -> Manifest {
        let t0 = Instant(iso: "2026-11-23T04:57:10.120Z")!
        let offset = UTCOffset(string: "+05:45")!
        let hash = String(repeating: "ab", count: 32)
        let place = GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: 5)
        func on(_ span: Int, _ n: Int, _ seconds: Int) -> Placement {
            Placement(id: id(n), at: t0.adding(milliseconds: Int64(seconds) * 1000 + (span == 2 ? 100_000 : 0)), utcOffset: offset,
                      spanId: id(span), offsetMs: seconds * 1000)
        }
        func free(_ n: Int, _ seconds: Int) -> Placement {
            Placement(id: id(n), at: t0.adding(milliseconds: Int64(seconds) * 1000), utcOffset: offset, spanId: nil, offsetMs: nil)
        }
        let inkStart = on(2, 16, 5)
        return Manifest(
            id: id(0), title: "Every kind", createdAt: t0, utcOffset: offset, timeZone: "Asia/Kathmandu",
            participants: ["P-014", "P-015"], researcher: "R",
            device: DeviceInfo(model: "iPad14,1", os: "iPadOS 27.1", app: "0.1.0"),
            startLocation: place,
            spans: [
                Span(id: id(1), file: "audio/audio-001.m4a", sha256: hash, startedAt: t0, utcOffset: offset,
                     timeZone: "Asia/Kathmandu", durationMs: 60_000, endedBy: .crashRecovered),
                Span(id: id(2), file: "audio/audio-002.m4a", sha256: hash, startedAt: t0.adding(milliseconds: 100_000),
                     utcOffset: offset, timeZone: "Asia/Kathmandu", durationMs: 30_000, endedBy: .stop),
            ],
            items: [
                .marker(on(1, 10, 0), type: .recordingStarted, detail: nil),
                .text(on(1, 11, 10), text: "A \"quoted\" line,\nand a second line.", modifiedAt: t0.adding(milliseconds: 20_000)),
                .photo(on(1, 12, 30), file: "photos/photo-0001.heic", sha256: hash, gps: place),
                .video(on(1, 13, 40), durationMs: 15_000, endedBy: .lock, sound: true, file: "video/clip-0001.mov", sha256: hash,
                       gps: GeoPoint(lat: -33.9, lon: -70.6, alt: nil, accuracyM: nil)),
                .marker(free(14, 80), type: .interrupted, detail: "crash-recovered"),
                .marker(on(2, 15, 0), type: .resumed, detail: nil),
                .ink(inkStart, endAt: inkStart.at.adding(milliseconds: 4000), file: "ink/ink-0001.png", sha256: hash,
                     data: "ink/ink-0001.drawing", dataSha256: hash,
                     strokes: [
                        InkStroke(at: inkStart.at, spanId: id(2), offsetMs: 5000, bounds: [12, 40.5, 180, 22]),
                        InkStroke(at: inkStart.at.adding(milliseconds: 4000), spanId: id(2), offsetMs: 9000, bounds: [12, 70, 96, 20]),
                     ]),
                .marker(on(2, 17, 30), type: .stopped, detail: nil),
                .marker(free(18, 140), type: .locationOff, detail: nil),
                .video(free(19, 150), durationMs: 4000, endedBy: .user, sound: false, file: "video/clip-0002.mov", sha256: hash, gps: nil),
                .marker(free(20, 160), type: .locationOn, detail: nil),
            ])
    }

    /// A session caught mid-recording: an open span, a clip still running, and no checksums yet.
    static func unfinished() -> Manifest {
        let start = Instant(iso: "2026-11-23T04:57:10.120Z")!
        let offset = UTCOffset(string: "+05:45")!
        func moment(_ seconds: Double) -> Moment {
            Moment(host: 50 + seconds, wall: start.adding(milliseconds: Int64(seconds * 1000)), utcOffset: offset, timeZone: "Asia/Kathmandu")
        }
        var timeline = SessionTimeline(title: "Still recording", participants: [], researcher: nil,
                                       device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                                       startLocation: nil, at: moment(0), ids: SeededIdSource(seed: 11))
        do {
            try timeline.startRecording(file: "audio/audio-001.m4a", at: moment(0))
            try timeline.addText("Typed while the recorder runs.", at: moment(12))
            try timeline.addPhoto(file: "photos/photo-0001.heic", gps: nil, at: moment(20))
            try timeline.startClip(file: "video/clip-0001.mov", gps: nil, at: moment(31))
        } catch {
            XCTFail("\(error)")
        }
        return timeline.manifest
    }

    func testValidSamplesAreWhatSwiftWrites() throws {
        XCTAssertEqual(Self.allKinds().problems(finished: true), [])
        XCTAssertEqual(Self.unfinished().problems(finished: false), [])
        XCTAssertNil(Self.unfinished().spans[0].endedBy)

        let folder = Self.format.appendingPathComponent("valid")
        for (name, manifest) in [("all-kinds", Self.allKinds()), ("unfinished", Self.unfinished())] {
            let url = folder.appendingPathComponent("\(name).json")
            let text = ManifestCoding.encode(manifest)
            if ProcessInfo.processInfo.environment["UPDATE_EXAMPLE"] == "1" {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
            XCTAssertEqual(try? String(contentsOf: url, encoding: .utf8), text,
                           "format/valid/\(name).json is out of date: run the tests once with UPDATE_EXAMPLE=1")
            XCTAssertEqual(try ManifestCoding.decode(text), manifest, name)
        }
    }

    func testEverySampleTheSchemaRejectsIsRejectedHereToo() throws {
        let folder = Self.format.appendingPathComponent("invalid")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".json") }.sorted()
        XCTAssertGreaterThanOrEqual(names.count, 15)
        for name in names {
            let text = try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
            if let manifest = try? ManifestCoding.decode(text) {
                XCTAssertFalse(manifest.problems(finished: true).isEmpty, "\(name) is accepted by the Swift reader")
            }
        }
    }
}
