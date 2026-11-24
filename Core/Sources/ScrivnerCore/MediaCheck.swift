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

        // The workbench joins a photo and a clip into one item when they share a Live Photo identifier.
        var filesByIdentifier: [String: [String]] = [:]
        for path in mediaPaths(in: manifest) {
            if let identifier = facts[path]?.contentIdentifier {
                filesByIdentifier[identifier, default: []].append(path)
            }
        }
        func common(_ path: String, _ file: MediaFacts) {
            if let identifier = file.contentIdentifier {
                let others = (filesByIdentifier[identifier] ?? []).filter { $0 != path }
                if others.isEmpty {
                    found.append(CheckFinding(.warning, path, "carries a Live Photo identifier"))
                } else {
                    found.append(CheckFinding(.problem, path,
                                              "shares a Live Photo identifier with \(others.joined(separator: ", ")), so the workbench would join them into one item"))
                }
            }
            if file.make == nil && file.model == nil {
                found.append(CheckFinding(.warning, path, "does not name the device that made it (make and model)"))
            }
        }

        // A path that is not a tidy relative path is never opened, so there is nothing to compare;
        // the folder check reports it.
        for span in manifest.spans where Manifest.isTidyRelativePath(span.file) {
            guard let file = readable(span.file, facts, &found) else { continue }
            common(span.file, file)
            created(span.file, file, at: span.startedAt, offset: span.utcOffset, &found)
            duration(span.file, file, expected: span.durationMs, &found)
            if file.location != nil || !file.strayLocationTags.isEmpty {
                found.append(CheckFinding(.problem, span.file, "carries a location; audio is never located" + whereFound(file)))
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
                guard Manifest.isTidyRelativePath(path), let file = readable(path, facts, &found) else { continue }
                common(path, file)
                photoTime(path, file, at: placement.at, offset: placement.utcOffset, &found)
                location(path, file, expected: gps, &found)
                if file.lens == nil {
                    found.append(CheckFinding(.warning, path, "does not name the lens"))
                }
            case .video(let placement, let durationMs, _, _, let path, _, let gps):
                guard Manifest.isTidyRelativePath(path), let file = readable(path, facts, &found) else { continue }
                common(path, file)
                created(path, file, at: placement.at, offset: placement.utcOffset, &found)
                location(path, file, expected: gps, &found)
                duration(path, file, expected: durationMs, &found)
            case .marker, .text, .ink:
                break   // Spec 6.3 asks nothing of handwriting files.
            }
        }
        return found
    }

    /// The files this check looks inside: every span's audio, every photo and every clip whose path
    /// is a tidy relative path, in the order `session.json` lists them. These are what ExifTool is given.
    public static func mediaPaths(in manifest: Manifest) -> [String] {
        var paths = manifest.spans.map(\.file)
        for item in manifest.items {
            switch item {
            case .photo(_, let file, _, _), .video(_, _, _, _, let file, _, _):
                paths.append(file)
            case .marker, .text, .ink:
                break
            }
        }
        var seen = Set<String>()
        return paths.filter { Manifest.isTidyRelativePath($0) && seen.insert($0).inserted }
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
            let (inFile, inSession) = moments(instant, at, offset)
            found.append(CheckFinding(.problem, path, "says it was taken at \(inFile) but session.json says \(inSession)"))
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
                let (inFile, inSession) = moments(instant, at, offset)
                found.append(CheckFinding(.problem, path, "says it was made at \(inFile) but session.json says \(inSession)"))
            }
        } else {
            found.append(CheckFinding(.problem, path, "has no creation time inside it (QuickTime CreateDate)"))
        }

        if let apple = file.creationDate, let stated = apple.offset, let instant = apple.instant {
            if apart(instant, at) > instantToleranceMs {
                let (inFile, inSession) = moments(instant, at, offset)
                found.append(CheckFinding(.problem, path,
                                          "says it was made at \(inFile) (Apple creation date) but session.json says \(inSession)"))
            }
            if stated != offset {
                found.append(CheckFinding(.problem, path,
                                          "says its offset from UTC is \(stated.string) but session.json says \(offset.string)"))
            }
        } else {
            found.append(CheckFinding(.problem, path, "has no creation date with the local offset inside it (Apple creation date)"))
        }
    }

    /// " (found in UserData:GPSCoordinates)" when the place is somewhere other than where spec 6.3 puts it.
    private static func whereFound(_ file: MediaFacts) -> String {
        file.strayLocationTags.isEmpty ? "" : " (found in \(file.strayLocationTags.joined(separator: ", ")))"
    }

    private static func location(_ path: String, _ file: MediaFacts, expected: GeoPoint?, _ found: inout [CheckFinding]) {
        // A place kept anywhere else in the file. The workbench would read it, so it counts.
        if expected != nil, !file.strayLocationTags.isEmpty {
            found.append(CheckFinding(.warning, path,
                                      "also carries a location in \(file.strayLocationTags.joined(separator: ", ")), which the workbench may read instead"))
        }
        switch (expected, file.location) {
        case (nil, nil):
            if !file.strayLocationTags.isEmpty {
                found.append(CheckFinding(.problem, path, "carries a location although session.json has none for it" + whereFound(file)))
            }
        case (.some, nil):
            found.append(CheckFinding(.problem, path, "has no location inside it although session.json gives one"))
        case (nil, .some):
            found.append(CheckFinding(.problem, path, "carries a location although session.json has none for it" + whereFound(file)))
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

    /// The two moments as the local clock showed them. The date is added to both when they fall
    /// on different days, or the same clock time on the wrong day would read as no difference at all.
    private static func moments(_ inFile: Instant, _ inSession: Instant, _ offset: UTCOffset) -> (String, String) {
        let a = LocalClock(inFile, offset: offset)
        let b = LocalClock(inSession, offset: offset)
        if (a.year, a.month, a.day) == (b.year, b.month, b.day) {
            return (clock(inFile, offset), clock(inSession, offset))
        }
        func dated(_ local: LocalClock, _ instant: Instant) -> String {
            let year = String(local.year)
            return String(repeating: "0", count: max(0, 4 - year.count)) + year + "-\(two(local.month))-\(two(local.day)) " + clock(instant, offset)
        }
        return (dated(a, inFile), dated(b, inSession))
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
