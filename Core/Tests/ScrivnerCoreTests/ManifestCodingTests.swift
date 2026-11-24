import XCTest
@testable import ScrivnerCore

final class ManifestCodingTests: XCTestCase {
    static let t0 = Instant(iso: "2026-11-23T10:42:10.120Z")!
    static let zero = UTCOffset(seconds: 0)
    static func sample() -> Manifest {
        let p = Placement(id: "00000000-0000-7000-8000-000000000002", at: t0.adding(milliseconds: 65_000), utcOffset: zero,
                          spanId: "00000000-0000-7000-8000-000000000001", offsetMs: 65_000)
        return Manifest(id: "00000000-0000-7000-8000-000000000000", title: "Market visit",
                        createdAt: t0, utcOffset: zero, timeZone: "Europe/Lisbon",
                        participants: ["P-014"], researcher: nil,
                        device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                        startLocation: GeoPoint(lat: 38.7223, lon: -9.1393, alt: nil, accuracyM: 5),
                        spans: [Span(id: "00000000-0000-7000-8000-000000000001", file: "audio/audio-001.m4a", sha256: nil,
                                     startedAt: t0, utcOffset: zero, timeZone: "Europe/Lisbon", durationMs: nil, endedBy: nil)],
                        items: [.text(p, text: "P-014 has run the stall since 2009.", modifiedAt: nil)])
    }

    func testEncodedTextIsExact() {
        XCTAssertEqual(ManifestCoding.encode(Self.sample()), """
        {
          "format": "ao-field-session",
          "version": 1,
          "id": "00000000-0000-7000-8000-000000000000",
          "title": "Market visit",
          "createdAt": "2026-11-23T10:42:10.120Z",
          "utcOffset": "+00:00",
          "timeZone": "Europe/Lisbon",
          "participants": ["P-014"],
          "device": {
            "model": "iPhone18,1",
            "os": "iOS 27.1",
            "app": "0.1.0"
          },
          "startLocation": {
            "lat": 38.7223,
            "lon": -9.1393,
            "accuracyM": 5.0
          },
          "spans": [
            {
              "id": "00000000-0000-7000-8000-000000000001",
              "file": "audio/audio-001.m4a",
              "startedAt": "2026-11-23T10:42:10.120Z",
              "utcOffset": "+00:00",
              "timeZone": "Europe/Lisbon"
            }
          ],
          "items": [
            {
              "id": "00000000-0000-7000-8000-000000000002",
              "kind": "text",
              "at": "2026-11-23T10:43:15.120Z",
              "utcOffset": "+00:00",
              "spanId": "00000000-0000-7000-8000-000000000001",
              "offsetMs": 65000,
              "text": "P-014 has run the stall since 2009."
            }
          ]
        }

        """)
    }
    func testEveryKindRoundTrips() throws {
        var m = Self.sample()
        let p = m.items[0].placement
        var free = p; free.spanId = nil; free.offsetMs = nil
        let hash = String(repeating: "ab", count: 32)
        m.researcher = "R"
        m.spans[0].sha256 = hash; m.spans[0].durationMs = 551_000; m.spans[0].endedBy = .crashRecovered
        m.items = [
            .marker(p, type: .recordingStarted, detail: nil),
            .marker(free, type: .interrupted, detail: "phone call"),
            .text(p, text: "a \"quoted\"\nline", modifiedAt: p.at.adding(milliseconds: 5)),
            .photo(p, file: "photos/photo-0001.heic", sha256: hash, gps: GeoPoint(lat: 1.5, lon: -2.5, alt: 3, accuracyM: nil)),
            .video(free, durationMs: 48_000, endedBy: .user, sound: false, file: "video/clip-0001.mov", sha256: nil, gps: nil),
            .ink(p, endAt: p.at.adding(milliseconds: 900), file: "ink/ink-0001.png", sha256: hash, data: "ink/ink-0001.drawing",
                 dataSha256: hash, strokes: [InkStroke(at: p.at, offsetMs: 65_000, bounds: [0, 0, 10.5, 4])]),
        ]
        XCTAssertEqual(try ManifestCoding.decode(ManifestCoding.encode(m)), m)
    }
    func testDecodeReportsThePathOfTheProblem() {
        func failure(_ edit: (String) -> String) -> ManifestDecodeError? {
            do { _ = try ManifestCoding.decode(edit(ManifestCoding.encode(Self.sample()))); return nil }
            catch { return error as? ManifestDecodeError }
        }
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2") }?.path, "version")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"offsetMs\": 65000", with: "\"offsetMs\": 65000.5") }?.path, "items[0].offsetMs")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"kind\": \"text\"", with: "\"kind\": \"song\"") }?.path, "items[0].kind")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "10:42:10.120Z\",\n      \"utcOffset", with: "10:42:10Z\",\n      \"utcOffset") }?.path, "spans[0].startedAt")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"title\": \"Market visit\",", with: "\"title\": \"Market visit\", \"extra\": 1,") }?.path, "extra")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"model\": \"iPhone18,1\",\n", with: "") }?.path, "device.model")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"lat\": 38.7223", with: "\"lat\": \"north\"") }?.path, "startLocation.lat")
    }
    func testDecodeAcceptsWholeNumbersForCoordinates() throws {
        let text = ManifestCoding.encode(Self.sample()).replacingOccurrences(of: "\"accuracyM\": 5.0", with: "\"accuracyM\": 5")
        XCTAssertEqual(try ManifestCoding.decode(text).startLocation?.accuracyM, 5)
    }
}
