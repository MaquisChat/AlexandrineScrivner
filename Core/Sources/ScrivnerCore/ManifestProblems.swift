import Foundation

/// Something inconsistent in a manifest, and where: `path` looks like `items[3].offsetMs`.
public struct ManifestProblem: Equatable, Sendable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

extension Manifest {
    /// Checks the things a well-shaped `session.json` can still get wrong: ids, file paths, positions
    /// on the audio, spans, hashes and coordinates. Empty when the manifest is consistent.
    ///
    /// With `finished: true` every span must also be closed and every file hashed.
    public func problems(finished: Bool) -> [ManifestProblem] {
        var found = ProblemList()
        let spansById = Dictionary(spans.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Ids: valid and all different.
        var seenIds = Set<String>()
        func checkId(_ id: String, _ path: String) {
            if !UUIDv7.isValid(id) {
                found.add(path, "is not a valid id")
            } else if !seenIds.insert(id).inserted {
                found.add(path, "is used by more than one thing")
            }
        }

        // File paths: relative, tidy, and each used once.
        var seenPaths = Set<String>()
        func checkPath(_ file: String, _ path: String) {
            if !Self.isTidyRelativePath(file) {
                found.add(path, "must be a plain relative path with no hidden or empty parts")
            } else if !seenPaths.insert(file).inserted {
                found.add(path, "names a file that is already listed")
            }
        }

        func checkHash(_ hash: String?, _ path: String, required: Bool) {
            if let hash {
                if !SHA256Hex.isValid(hash) { found.add(path, "must be 64 lower-case hex characters") }
            } else if required {
                found.add(path, "is missing: a finished session lists a hash for every file")
            }
        }

        func checkPoint(_ point: GeoPoint?, _ path: String) {
            guard let point else { return }
            if !(-90.0...90.0).contains(point.lat) { found.add(path + ".lat", "must be between -90 and 90") }
            if !(-180.0...180.0).contains(point.lon) { found.add(path + ".lon", "must be between -180 and 180") }
            if let alt = point.alt, !alt.isFinite { found.add(path + ".alt", "must be an ordinary number") }
            if let accuracy = point.accuracyM, !accuracy.isFinite { found.add(path + ".accuracyM", "must be an ordinary number") }
        }

        // An offset from UTC that could not be written as "+HH:MM" and read back.
        func checkOffset(_ offset: UTCOffset, _ path: String) {
            if abs(offset.seconds) > 18 * 3600 { found.add(path, "must be between -18:00 and +18:00") }
        }

        // Where something falls on the audio: both parts or neither, on a span that exists, inside it.
        func checkPosition(spanId: String?, offsetMs: Int?, _ base: String) {
            if (spanId == nil) != (offsetMs == nil) {
                found.add(base + ".spanId", "spanId and offsetMs go together")
            } else if let spanId, let offset = offsetMs {
                if let span = spansById[spanId] {
                    if offset < 0 {
                        found.add(base + ".offsetMs", "must not be negative")
                    } else if let duration = span.durationMs, offset > duration {
                        found.add(base + ".offsetMs", "is past the end of its span")
                    }
                } else {
                    found.add(base + ".spanId", "names a span that does not exist")
                }
            }
        }

        // Top level.
        checkId(id, "id")
        checkOffset(utcOffset, "utcOffset")
        checkPoint(startLocation, "startLocation")

        // Spans.
        for (index, span) in spans.enumerated() {
            let base = "spans[\(index)]"
            checkId(span.id, base + ".id")
            checkPath(span.file, base + ".file")
            checkOffset(span.utcOffset, base + ".utcOffset")

            let isOpen = span.endedBy == nil
            if (span.durationMs == nil) != isOpen {
                found.add(base + ".endedBy", "durationMs and endedBy go together")
            }
            if let duration = span.durationMs, duration < 0 {
                found.add(base + ".durationMs", "must not be negative")
            }
            if isOpen && index != spans.count - 1 {
                found.add(base + ".endedBy", "only the last span may still be open")
            }
            if isOpen && finished {
                found.add(base + ".endedBy", "is missing: a finished session has no open span")
            }
            checkHash(span.sha256, base + ".sha256", required: finished)
        }

        // Items.
        for (index, item) in items.enumerated() {
            let base = "items[\(index)]"
            let placement = item.placement
            checkId(placement.id, base + ".id")

            switch item {
            case .photo(_, let file, _, _), .video(_, _, _, _, let file, _, _):
                checkPath(file, base + ".file")
            case .ink(_, _, let file, _, let data, _, _):
                checkPath(file, base + ".file")
                checkPath(data, base + ".data")
            case .marker, .text:
                break
            }

            checkOffset(placement.utcOffset, base + ".utcOffset")
            checkPosition(spanId: placement.spanId, offsetMs: placement.offsetMs, base)

            switch item {
            case .photo(_, _, let sha256, let gps):
                checkHash(sha256, base + ".sha256", required: finished)
                checkPoint(gps, base + ".gps")
            case .video(_, let durationMs, _, _, _, let sha256, let gps):
                if let durationMs, durationMs < 0 { found.add(base + ".durationMs", "must not be negative") }
                checkHash(sha256, base + ".sha256", required: finished)
                checkPoint(gps, base + ".gps")
            case .ink(_, _, _, let sha256, _, let dataSha256, let strokes):
                checkHash(sha256, base + ".sha256", required: finished)
                checkHash(dataSha256, base + ".dataSha256", required: finished)
                for (strokeIndex, stroke) in strokes.enumerated() {
                    let strokeBase = base + ".strokes[\(strokeIndex)]"
                    checkPosition(spanId: stroke.spanId, offsetMs: stroke.offsetMs, strokeBase)
                    if stroke.bounds.count != 4 {
                        found.add(strokeBase + ".bounds", "must have exactly four numbers")
                    } else if !stroke.bounds.allSatisfy(\.isFinite) {
                        found.add(strokeBase + ".bounds", "must be ordinary numbers")
                    }
                }
            case .marker, .text:
                break
            }
        }

        return found.problems
    }

    /// Relative, forward slashes only, no empty, "." or ".." part, and no part starting with a dot.
    static func isTidyRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("\\") else { return false }
        for part in path.split(separator: "/", omittingEmptySubsequences: false) {
            if part.isEmpty || part.hasPrefix(".") { return false }
        }
        return true
    }
}

/// Problems in the order found, at most one per path.
private struct ProblemList {
    private(set) var problems: [ManifestProblem] = []
    private var paths = Set<String>()

    mutating func add(_ path: String, _ message: String) {
        guard paths.insert(path).inserted else { return }
        problems.append(ManifestProblem(path: path, message: message))
    }
}
