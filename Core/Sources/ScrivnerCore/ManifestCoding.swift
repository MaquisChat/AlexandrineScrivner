import Foundation

/// What is wrong with a `session.json`, and where: `path` looks like `items[3].offsetMs`.
public struct ManifestDecodeError: Error, Equatable {
    public let path: String
    public let message: String

    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

/// Turns a manifest into the text of `session.json` and back.
/// The schema in `format/field-session.v1.schema.json` describes the same shape.
public enum ManifestCoding {
    public static func encode(_ manifest: Manifest) -> String {
        json(manifest).written()
    }

    // MARK: - Writing

    public static func json(_ manifest: Manifest) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [
            ("format", .string(Manifest.format)),
            ("version", .int(Manifest.version)),
            ("id", .string(manifest.id)),
            ("title", .string(manifest.title)),
            ("createdAt", .string(manifest.createdAt.iso)),
            ("utcOffset", .string(manifest.utcOffset.string)),
            ("timeZone", .string(manifest.timeZone)),
            ("participants", .array(manifest.participants.map { .string($0) })),
        ]
        if let researcher = manifest.researcher { pairs.append(("researcher", .string(researcher))) }
        pairs.append(("device", .object([
            ("model", .string(manifest.device.model)),
            ("os", .string(manifest.device.os)),
            ("app", .string(manifest.device.app)),
        ])))
        if let start = manifest.startLocation { pairs.append(("startLocation", json(start))) }
        pairs.append(("spans", .array(manifest.spans.map(json))))
        pairs.append(("items", .array(manifest.items.map(json))))
        return .object(pairs)
    }

    private static func json(_ point: GeoPoint) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [("lat", .double(point.lat)), ("lon", .double(point.lon))]
        if let alt = point.alt { pairs.append(("alt", .double(alt))) }
        if let accuracy = point.accuracyM { pairs.append(("accuracyM", .double(accuracy))) }
        return .object(pairs)
    }

    private static func json(_ span: Span) -> JSONValue {
        var pairs: [(key: String, value: JSONValue)] = [("id", .string(span.id)), ("file", .string(span.file))]
        if let hash = span.sha256 { pairs.append(("sha256", .string(hash))) }
        pairs.append(("startedAt", .string(span.startedAt.iso)))
        pairs.append(("utcOffset", .string(span.utcOffset.string)))
        pairs.append(("timeZone", .string(span.timeZone)))
        if let duration = span.durationMs { pairs.append(("durationMs", .int(duration))) }
        if let end = span.endedBy { pairs.append(("endedBy", .string(end.rawValue))) }
        return .object(pairs)
    }

    private static func json(_ item: Item) -> JSONValue {
        let p = item.placement
        var pairs: [(key: String, value: JSONValue)] = [("id", .string(p.id)), ("kind", .string(item.kind))]
        if case .marker(_, let type, _) = item { pairs.append(("type", .string(type.rawValue))) }
        pairs.append(("at", .string(p.at.iso)))
        if case .ink(_, let endAt?, _, _, _, _, _) = item { pairs.append(("endAt", .string(endAt.iso))) }
        pairs.append(("utcOffset", .string(p.utcOffset.string)))
        if let spanId = p.spanId { pairs.append(("spanId", .string(spanId))) }
        if let offset = p.offsetMs { pairs.append(("offsetMs", .int(offset))) }

        switch item {
        case .marker(_, _, let detail):
            if let detail { pairs.append(("detail", .string(detail))) }
        case .text(_, let text, let modifiedAt):
            pairs.append(("text", .string(text)))
            if let modifiedAt { pairs.append(("modifiedAt", .string(modifiedAt.iso))) }
        case .photo(_, let file, let sha256, let gps):
            pairs.append(("file", .string(file)))
            if let sha256 { pairs.append(("sha256", .string(sha256))) }
            if let gps { pairs.append(("gps", json(gps))) }
        case .video(_, let durationMs, let endedBy, let sound, let file, let sha256, let gps):
            if let durationMs { pairs.append(("durationMs", .int(durationMs))) }
            if let endedBy { pairs.append(("endedBy", .string(endedBy.rawValue))) }
            pairs.append(("sound", .bool(sound)))
            pairs.append(("file", .string(file)))
            if let sha256 { pairs.append(("sha256", .string(sha256))) }
            if let gps { pairs.append(("gps", json(gps))) }
        case .ink(_, _, let file, let sha256, let data, let dataSha256, let strokes):
            pairs.append(("file", .string(file)))
            if let sha256 { pairs.append(("sha256", .string(sha256))) }
            pairs.append(("data", .string(data)))
            if let dataSha256 { pairs.append(("dataSha256", .string(dataSha256))) }
            pairs.append(("strokes", .array(strokes.map { stroke in
                var strokePairs: [(key: String, value: JSONValue)] = [("at", .string(stroke.at.iso))]
                if let offset = stroke.offsetMs { strokePairs.append(("offsetMs", .int(offset))) }
                strokePairs.append(("bounds", .array(stroke.bounds.map { .double($0) })))
                return .object(strokePairs)
            })))
        }
        return .object(pairs)
    }

    // MARK: - Reading

    /// Strict: unknown keys, missing keys and wrong types are all errors that name their path.
    public static func decode(_ text: String) throws -> Manifest {
        var top = try ObjectReader(try JSONValue.parse(text), path: "")

        let format = try top.string("format")
        guard format == Manifest.format else {
            throw ManifestDecodeError(path: "format", message: "must be \"\(Manifest.format)\"")
        }
        let version = try top.int("version")
        guard version == Manifest.version else {
            throw ManifestDecodeError(path: "version", message: "must be \(Manifest.version)")
        }

        let id = try top.string("id")
        let title = try top.string("title")
        let createdAt = try top.instant("createdAt")
        let utcOffset = try top.offset("utcOffset")
        let timeZone = try top.string("timeZone")
        let participants = try top.list("participants").map { value, path in try Read.string(value, path) }
        let researcher = try top.optional("researcher").map { try Read.string($0.value, $0.path) }

        let (deviceValue, devicePath) = try top.required("device")
        var deviceReader = try ObjectReader(deviceValue, path: devicePath)
        let device = DeviceInfo(model: try deviceReader.string("model"), os: try deviceReader.string("os"),
                                app: try deviceReader.string("app"))
        try deviceReader.finish()

        let startLocation = try top.optional("startLocation").map { try geoPoint($0.value, $0.path) }
        let spans = try top.list("spans").map { value, path in try span(value, path) }
        let items = try top.list("items").map { value, path in try item(value, path) }
        try top.finish()

        return Manifest(id: id, title: title, createdAt: createdAt, utcOffset: utcOffset, timeZone: timeZone,
                        participants: participants, researcher: researcher, device: device,
                        startLocation: startLocation, spans: spans, items: items)
    }

    private static func geoPoint(_ value: JSONValue, _ path: String) throws -> GeoPoint {
        var reader = try ObjectReader(value, path: path)
        let point = GeoPoint(lat: try reader.double("lat"), lon: try reader.double("lon"),
                             alt: try reader.optional("alt").map { try Read.double($0.value, $0.path) },
                             accuracyM: try reader.optional("accuracyM").map { try Read.double($0.value, $0.path) })
        try reader.finish()
        return point
    }

    private static func span(_ value: JSONValue, _ path: String) throws -> Span {
        var reader = try ObjectReader(value, path: path)
        let span = Span(id: try reader.string("id"),
                        file: try reader.string("file"),
                        sha256: try reader.optional("sha256").map { try Read.string($0.value, $0.path) },
                        startedAt: try reader.instant("startedAt"),
                        utcOffset: try reader.offset("utcOffset"),
                        timeZone: try reader.string("timeZone"),
                        durationMs: try reader.optional("durationMs").map { try Read.int($0.value, $0.path) },
                        endedBy: try reader.optional("endedBy").map { try Read.choice(SpanEnd.self, $0.value, $0.path) })
        try reader.finish()
        return span
    }

    private static func item(_ value: JSONValue, _ path: String) throws -> Item {
        var reader = try ObjectReader(value, path: path)
        let id = try reader.string("id")
        let (kindValue, kindPath) = try reader.required("kind")
        let kind = try Read.string(kindValue, kindPath)
        guard ["marker", "text", "photo", "video", "ink"].contains(kind) else {
            throw ManifestDecodeError(path: kindPath, message: "is not one of: marker, text, photo, video, ink")
        }
        let markerType = kind == "marker" ? try reader.choice(MarkerType.self, "type") : nil
        let at = try reader.instant("at")
        let endAt = kind == "ink" ? try reader.optional("endAt").map { try Read.instant($0.value, $0.path) } : nil
        let placement = Placement(id: id, at: at, utcOffset: try reader.offset("utcOffset"),
                                  spanId: try reader.optional("spanId").map { try Read.string($0.value, $0.path) },
                                  offsetMs: try reader.optional("offsetMs").map { try Read.int($0.value, $0.path) })

        let result: Item
        switch kind {
        case "marker":
            result = .marker(placement, type: markerType!,
                             detail: try reader.optional("detail").map { try Read.string($0.value, $0.path) })
        case "text":
            result = .text(placement, text: try reader.string("text"),
                           modifiedAt: try reader.optional("modifiedAt").map { try Read.instant($0.value, $0.path) })
        case "photo":
            result = .photo(placement, file: try reader.string("file"),
                            sha256: try reader.optional("sha256").map { try Read.string($0.value, $0.path) },
                            gps: try reader.optional("gps").map { try geoPoint($0.value, $0.path) })
        case "video":
            let durationMs = try reader.optional("durationMs").map { try Read.int($0.value, $0.path) }
            let endedBy = try reader.optional("endedBy").map { try Read.choice(ClipEnd.self, $0.value, $0.path) }
            let (soundValue, soundPath) = try reader.required("sound")
            result = .video(placement, durationMs: durationMs, endedBy: endedBy,
                            sound: try Read.bool(soundValue, soundPath),
                            file: try reader.string("file"),
                            sha256: try reader.optional("sha256").map { try Read.string($0.value, $0.path) },
                            gps: try reader.optional("gps").map { try geoPoint($0.value, $0.path) })
        default:    // ink
            let file = try reader.string("file")
            let sha256 = try reader.optional("sha256").map { try Read.string($0.value, $0.path) }
            let data = try reader.string("data")
            let dataSha256 = try reader.optional("dataSha256").map { try Read.string($0.value, $0.path) }
            let strokes = try reader.list("strokes").map { strokeValue, strokePath -> InkStroke in
                var strokeReader = try ObjectReader(strokeValue, path: strokePath)
                let strokeAt = try strokeReader.instant("at")
                let offset = try strokeReader.optional("offsetMs").map { try Read.int($0.value, $0.path) }
                let boundsList = try strokeReader.list("bounds")
                guard boundsList.count == 4 else {
                    throw ManifestDecodeError(path: strokePath + ".bounds", message: "must have exactly four numbers")
                }
                let bounds = try boundsList.map { try Read.double($0.value, $0.path) }
                try strokeReader.finish()
                return InkStroke(at: strokeAt, offsetMs: offset, bounds: bounds)
            }
            result = .ink(placement, endAt: endAt, file: file, sha256: sha256, data: data,
                          dataSha256: dataSha256, strokes: strokes)
        }
        try reader.finish()
        return result
    }
}

// MARK: - Reading helpers

/// Reads the keys of one JSON object, remembers which were asked for, and complains about the rest.
private struct ObjectReader {
    let path: String
    let pairs: [(key: String, value: JSONValue)]
    var used = Set<String>()

    init(_ value: JSONValue, path: String) throws {
        guard case .object(let pairs) = value else {
            throw ManifestDecodeError(path: path, message: "must be an object")
        }
        self.path = path
        self.pairs = pairs
    }

    func childPath(_ key: String) -> String {
        path.isEmpty ? key : path + "." + key
    }

    mutating func optional(_ key: String) -> (value: JSONValue, path: String)? {
        used.insert(key)
        guard let value = pairs.first(where: { $0.key == key })?.value else { return nil }
        return (value, childPath(key))
    }

    mutating func required(_ key: String) throws -> (JSONValue, String) {
        guard let found = optional(key) else {
            throw ManifestDecodeError(path: childPath(key), message: "is missing")
        }
        return (found.value, found.path)
    }

    mutating func string(_ key: String) throws -> String {
        let (value, path) = try required(key)
        return try Read.string(value, path)
    }

    mutating func int(_ key: String) throws -> Int {
        let (value, path) = try required(key)
        return try Read.int(value, path)
    }

    mutating func double(_ key: String) throws -> Double {
        let (value, path) = try required(key)
        return try Read.double(value, path)
    }

    mutating func instant(_ key: String) throws -> Instant {
        let (value, path) = try required(key)
        return try Read.instant(value, path)
    }

    mutating func offset(_ key: String) throws -> UTCOffset {
        let (value, path) = try required(key)
        return try Read.offset(value, path)
    }

    mutating func choice<T: RawRepresentable & CaseIterable>(_ type: T.Type, _ key: String) throws -> T where T.RawValue == String {
        let (value, path) = try required(key)
        return try Read.choice(type, value, path)
    }

    /// The elements of a required list, each with its own path.
    mutating func list(_ key: String) throws -> [(value: JSONValue, path: String)] {
        let (value, path) = try required(key)
        guard case .array(let items) = value else {
            throw ManifestDecodeError(path: path, message: "must be a list")
        }
        return items.enumerated().map { ($0.element, "\(path)[\($0.offset)]") }
    }

    /// Any key nobody asked for is not part of the format.
    func finish() throws {
        if let extra = pairs.first(where: { !used.contains($0.key) }) {
            throw ManifestDecodeError(path: childPath(extra.key), message: "is not a key this format has")
        }
    }
}

private enum Read {
    static func string(_ value: JSONValue, _ path: String) throws -> String {
        guard case .string(let text) = value else { throw ManifestDecodeError(path: path, message: "must be text") }
        return text
    }

    static func int(_ value: JSONValue, _ path: String) throws -> Int {
        guard case .int(let number) = value else {
            throw ManifestDecodeError(path: path, message: "must be a whole number")
        }
        return number
    }

    static func double(_ value: JSONValue, _ path: String) throws -> Double {
        switch value {
        case .double(let number): return number
        case .int(let number): return Double(number)
        default: throw ManifestDecodeError(path: path, message: "must be a number")
        }
    }

    static func bool(_ value: JSONValue, _ path: String) throws -> Bool {
        guard case .bool(let flag) = value else { throw ManifestDecodeError(path: path, message: "must be true or false") }
        return flag
    }

    static func instant(_ value: JSONValue, _ path: String) throws -> Instant {
        guard case .string(let text) = value, let instant = Instant(iso: text) else {
            throw ManifestDecodeError(path: path, message: "must be a time like 2026-11-23T10:42:10.120Z")
        }
        return instant
    }

    static func offset(_ value: JSONValue, _ path: String) throws -> UTCOffset {
        guard case .string(let text) = value, let offset = UTCOffset(string: text) else {
            throw ManifestDecodeError(path: path, message: "must be an offset like +01:00")
        }
        return offset
    }

    static func choice<T: RawRepresentable & CaseIterable>(_ type: T.Type, _ value: JSONValue, _ path: String) throws -> T where T.RawValue == String {
        guard case .string(let text) = value, let choice = T(rawValue: text) else {
            let allowed = T.allCases.map(\.rawValue).joined(separator: ", ")
            throw ManifestDecodeError(path: path, message: "is not one of: \(allowed)")
        }
        return choice
    }
}
