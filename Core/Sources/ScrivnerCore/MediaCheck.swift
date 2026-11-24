import Foundation

/// Compares what each media file says about itself with what `session.json` says about it.
///
/// The research workbench reads times and places from the files, not from `session.json`, so the
/// two have to agree: the same instant to within a second, the same offset from UTC, the same place.
public enum MediaCheck {
    static let instantToleranceMs: Int64 = 1000
    static let durationToleranceMs = 1000
    static let degreesTolerance = 0.0001
    static let metresTolerance = 1.0

    /// `facts` is keyed by the path each file has in `session.json`.
    public static func findings(for manifest: Manifest, facts: [String: MediaFacts]) -> [CheckFinding] {
        var found: [CheckFinding] = []

        for span in manifest.spans {
            guard let file = readable(span.file, facts, &found) else { continue }
            common(span.file, file, &found)
            created(span.file, file, at: span.startedAt, offset: span.utcOffset, &found)
            duration(span.file, file, expected: span.durationMs, &found)
            if file.location != nil {
                found.append(CheckFinding(.problem, span.file, "carries a location; audio is never located"))
            }
            if let length = file.durationMs, let furthest = furthestOffset(on: span.id, in: manifest),
               furthest > length + durationToleranceMs {
                found.append(CheckFinding(.problem, span.file,
                                          "is \(clock(length)) long, but an item in session.json sits at \(clock(furthest)) on it"))
            }
        }

        for item in manifest.items {
            switch item {
            case .photo(let placement, let path, _, let gps):
                guard let file = readable(path, facts, &found) else { continue }
                common(path, file, &found)
                photoTime(path, file, at: placement.at, offset: placement.utcOffset, &found)
                location(path, file, expected: gps, &found)
                if file.lens == nil {
                    found.append(CheckFinding(.warning, path, "does not name the lens"))
                }
            case .video(let placement, let durationMs, _, _, let path, _, let gps):
                guard let file = readable(path, facts, &found) else { continue }
                common(path, file, &found)
                created(path, file, at: placement.at, offset: placement.utcOffset, &found)
                location(path, file, expected: gps, &found)
                duration(path, file, expected: durationMs, &found)
            case .marker, .text, .ink:
                break   // Spec 6.3 asks nothing of handwriting files.
            }
        }
        return found
    }

    // MARK: - Rules

    /// The file's facts, or nil (with a problem recorded) when ExifTool could not read it.
    private static func readable(_ path: String, _ facts: [String: MediaFacts], _ found: inout [CheckFinding]) -> MediaFacts? {
        guard let file = facts[path] else {
            found.append(CheckFinding(.problem, path, "could not be read: ExifTool returned nothing for it"))
            return nil
        }
        if let error = file.error {
            found.append(CheckFinding(.problem, path, "could not be read: \(error)"))
            return nil
        }
        return file
    }

    private static func common(_ path: String, _ file: MediaFacts, _ found: inout [CheckFinding]) {
        if file.contentIdentifier != nil {
            found.append(CheckFinding(.problem, path,
                                      "carries a Live Photo identifier, which would make the workbench pair it with another file"))
        }
        if file.make == nil && file.model == nil {
            found.append(CheckFinding(.warning, path, "does not name the device that made it (make and model)"))
        }
    }

    private static func photoTime(_ path: String, _ file: MediaFacts, at: Instant, offset: UTCOffset, _ found: inout [CheckFinding]) {
        guard let original = file.original else {
            found.append(CheckFinding(.problem, path, "has no capture time inside it (EXIF DateTimeOriginal)"))
            return
        }
        guard let stated = original.offset, let instant = original.instant else {
            found.append(CheckFinding(.problem, path, "has no time zone offset inside it (EXIF OffsetTimeOriginal)"))
            return
        }
        if apart(instant, at) > instantToleranceMs {
            found.append(CheckFinding(.problem, path,
                                      "says it was taken at \(clock(instant, offset)) but session.json says \(clock(at, offset))"))
        }
        if stated != offset {
            found.append(CheckFinding(.problem, path,
                                      "says its offset from UTC is \(stated.string) but session.json says \(offset.string)"))
        }
        if !original.hasFraction {
            found.append(CheckFinding(.warning, path, "capture time has no sub-seconds"))
        }
    }

    /// Audio and video: the QuickTime creation time and Apple's creation date.
    private static func created(_ path: String, _ file: MediaFacts, at: Instant, offset: UTCOffset, _ found: inout [CheckFinding]) {
        if let instant = file.created?.instant {
            if apart(instant, at) > instantToleranceMs {
                found.append(CheckFinding(.problem, path,
                                          "says it was made at \(clock(instant, offset)) but session.json says \(clock(at, offset))"))
            }
        } else {
            found.append(CheckFinding(.problem, path, "has no creation time inside it (QuickTime CreateDate)"))
        }

        if let apple = file.creationDate, let stated = apple.offset, let instant = apple.instant {
            if apart(instant, at) > instantToleranceMs {
                found.append(CheckFinding(.problem, path,
                                          "says it was made at \(clock(instant, offset)) (Apple creation date) but session.json says \(clock(at, offset))"))
            }
            if stated != offset {
                found.append(CheckFinding(.problem, path,
                                          "says its offset from UTC is \(stated.string) but session.json says \(offset.string)"))
            }
        } else {
            found.append(CheckFinding(.problem, path, "has no creation date with the local offset inside it (Apple creation date)"))
        }
    }

    private static func location(_ path: String, _ file: MediaFacts, expected: GeoPoint?, _ found: inout [CheckFinding]) {
        switch (expected, file.location) {
        case (nil, nil):
            break
        case (.some, nil):
            found.append(CheckFinding(.problem, path, "has no location inside it although session.json gives one"))
        case (nil, .some):
            found.append(CheckFinding(.problem, path, "carries a location although session.json has none for it"))
        case (let wanted?, let actual?):
            if abs(wanted.lat - actual.lat) > degreesTolerance || abs(wanted.lon - actual.lon) > degreesTolerance {
                found.append(CheckFinding(.problem, path,
                                          "says it was made at \(degrees(actual.lat)), \(degrees(actual.lon)) but session.json says \(degrees(wanted.lat)), \(degrees(wanted.lon))"))
            } else if let wantedAlt = wanted.alt, let actualAlt = actual.alt, abs(wantedAlt - actualAlt) > metresTolerance {
                found.append(CheckFinding(.problem, path,
                                          "says its altitude is \(metres(actualAlt)) m but session.json says \(metres(wantedAlt)) m"))
            }
        }
    }

    private static func duration(_ path: String, _ file: MediaFacts, expected: Int?, _ found: inout [CheckFinding]) {
        guard let actual = file.durationMs, let expected, abs(actual - expected) > durationToleranceMs else { return }
        found.append(CheckFinding(.warning, path, "is \(clock(actual)) long but session.json says \(clock(expected))"))
    }

    /// The largest position anything has on a span, strokes of handwriting included.
    private static func furthestOffset(on spanId: String, in manifest: Manifest) -> Int? {
        var furthest: Int?
        func note(_ offset: Int?) {
            if let offset { furthest = max(furthest ?? 0, offset) }
        }
        for item in manifest.items {
            if item.placement.spanId == spanId { note(item.placement.offsetMs) }
            if case .ink(_, _, _, _, _, _, let strokes) = item {
                for stroke in strokes where stroke.spanId == spanId { note(stroke.offsetMs) }
            }
        }
        return furthest
    }

    // MARK: - Wording

    private static func apart(_ a: Instant, _ b: Instant) -> Int64 {
        abs(a.millisecondsSince1970 - b.millisecondsSince1970)
    }

    private static func two(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// A moment as the local clock showed it: `HH:MM:SS`.
    private static func clock(_ instant: Instant, _ offset: UTCOffset) -> String {
        let local = LocalClock(instant, offset: offset)
        return "\(two(local.hour)):\(two(local.minute)):\(two(local.second))"
    }

    /// A length or position: `M:SS`.
    private static func clock(_ milliseconds: Int) -> String {
        let seconds = Int((Double(milliseconds) / 1000).rounded())
        return "\(seconds / 60):\(two(seconds % 60))"
    }

    /// Five decimal places, about a metre.
    private static func degrees(_ value: Double) -> String {
        let scaled = Int64((abs(value) * 100_000).rounded())
        let fraction = String(scaled % 100_000)
        return (value < 0 ? "-" : "") + "\(scaled / 100_000)." + String(repeating: "0", count: 5 - fraction.count) + fraction
    }

    private static func metres(_ value: Double) -> String {
        String(Int64(value.rounded()))
    }
}
