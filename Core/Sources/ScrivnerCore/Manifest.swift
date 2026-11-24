import Foundation

/// A place on the earth.
public struct GeoPoint: Equatable, Sendable {
    public var lat: Double
    public var lon: Double
    public var alt: Double?
    public var accuracyM: Double?

    public init(lat: Double, lon: Double, alt: Double?, accuracyM: Double?) {
        self.lat = lat
        self.lon = lon
        self.alt = alt
        self.accuracyM = accuracyM
    }
}

/// The device a session was made on. Never the device's own name.
public struct DeviceInfo: Equatable, Sendable {
    public var model: String
    public var os: String
    public var app: String

    public init(model: String, os: String, app: String) {
        self.model = model
        self.os = os
        self.app = app
    }
}

/// Why a stretch of recording ended.
public enum SpanEnd: String, Sendable, CaseIterable {
    case pause
    case stop
    case interruption
    case crashRecovered = "crash-recovered"
}

/// One unbroken stretch of recorded audio, in a file of its own.
public struct Span: Equatable, Sendable {
    public var id: String
    public var file: String
    public var sha256: String?
    public var startedAt: Instant
    public var utcOffset: UTCOffset
    public var timeZone: String
    /// Nil while the span is still being recorded.
    public var durationMs: Int?
    /// Nil while the span is still being recorded.
    public var endedBy: SpanEnd?

    public init(id: String, file: String, sha256: String?, startedAt: Instant, utcOffset: UTCOffset,
                timeZone: String, durationMs: Int?, endedBy: SpanEnd?) {
        self.id = id
        self.file = file
        self.sha256 = sha256
        self.startedAt = startedAt
        self.utcOffset = utcOffset
        self.timeZone = timeZone
        self.durationMs = durationMs
        self.endedBy = endedBy
    }
}

public enum MarkerType: String, Sendable, CaseIterable {
    case recordingStarted = "recording-started"
    case paused
    case resumed
    case stopped
    case interrupted
    case locationOff = "location-off"
    case locationOn = "location-on"
}

/// Why a video clip ended.
public enum ClipEnd: String, Sendable, CaseIterable {
    case user
    case background
    case lock
    case interruption
    case stop
}

/// What every item has: who it is, when it was made, and where it falls on the audio.
public struct Placement: Equatable, Sendable {
    public var id: String
    public var at: Instant
    public var utcOffset: UTCOffset
    /// Nil, together with `offsetMs`, when nothing was recording.
    public var spanId: String?
    public var offsetMs: Int?

    public init(id: String, at: Instant, utcOffset: UTCOffset, spanId: String?, offsetMs: Int?) {
        self.id = id
        self.at = at
        self.utcOffset = utcOffset
        self.spanId = spanId
        self.offsetMs = offsetMs
    }
}

public struct InkStroke: Equatable, Sendable {
    public var at: Instant
    /// The recording span this stroke falls on. A handwriting block can run on across a pause,
    /// so each stroke says for itself which span it is on. Nil when nothing was recording.
    public var spanId: String?
    public var offsetMs: Int?
    /// x, y, width, height on the page.
    public var bounds: [Double]

    public init(at: Instant, spanId: String?, offsetMs: Int?, bounds: [Double]) {
        self.at = at
        self.spanId = spanId
        self.offsetMs = offsetMs
        self.bounds = bounds
    }
}

extension Manifest {
    /// The title to show. A session the owner has not named shows its local date and start time,
    /// `2026-11-23 10:42`; the title kept in the file stays empty, so the folder's name does not
    /// say the date twice.
    public var displayTitle: String {
        guard title.isEmpty else { return title }
        let clock = LocalClock(createdAt, offset: utcOffset)
        func padded(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(padded(clock.year, 4))-\(padded(clock.month, 2))-\(padded(clock.day, 2)) \(padded(clock.hour, 2)):\(padded(clock.minute, 2))"
    }
}

/// One thing on the page.
public enum Item: Equatable, Sendable {
    case marker(Placement, type: MarkerType, detail: String?)
    case text(Placement, text: String, modifiedAt: Instant?)
    case photo(Placement, file: String, sha256: String?, gps: GeoPoint?)
    case video(Placement, durationMs: Int?, endedBy: ClipEnd?, sound: Bool, file: String, sha256: String?, gps: GeoPoint?)
    case ink(Placement, endAt: Instant?, file: String, sha256: String?, data: String, dataSha256: String?, strokes: [InkStroke])

    public var placement: Placement {
        get {
            switch self {
            case .marker(let p, _, _): return p
            case .text(let p, _, _): return p
            case .photo(let p, _, _, _): return p
            case .video(let p, _, _, _, _, _, _): return p
            case .ink(let p, _, _, _, _, _, _): return p
            }
        }
        set {
            switch self {
            case .marker(_, let type, let detail):
                self = .marker(newValue, type: type, detail: detail)
            case .text(_, let text, let modifiedAt):
                self = .text(newValue, text: text, modifiedAt: modifiedAt)
            case .photo(_, let file, let sha256, let gps):
                self = .photo(newValue, file: file, sha256: sha256, gps: gps)
            case .video(_, let durationMs, let endedBy, let sound, let file, let sha256, let gps):
                self = .video(newValue, durationMs: durationMs, endedBy: endedBy, sound: sound, file: file, sha256: sha256, gps: gps)
            case .ink(_, let endAt, let file, let sha256, let data, let dataSha256, let strokes):
                self = .ink(newValue, endAt: endAt, file: file, sha256: sha256, data: data, dataSha256: dataSha256, strokes: strokes)
            }
        }
    }

    /// "marker", "text", "photo", "video" or "ink".
    public var kind: String {
        switch self {
        case .marker: return "marker"
        case .text: return "text"
        case .photo: return "photo"
        case .video: return "video"
        case .ink: return "ink"
        }
    }
}

/// Everything `session.json` holds.
public struct Manifest: Equatable, Sendable {
    public static let format = "ao-field-session"
    public static let version = 1

    public var id: String
    public var title: String
    public var createdAt: Instant
    public var utcOffset: UTCOffset
    public var timeZone: String
    public var participants: [String]
    public var researcher: String?
    public var device: DeviceInfo
    public var startLocation: GeoPoint?
    public var spans: [Span]
    public var items: [Item]

    public init(id: String, title: String, createdAt: Instant, utcOffset: UTCOffset, timeZone: String,
                participants: [String], researcher: String?, device: DeviceInfo, startLocation: GeoPoint?,
                spans: [Span], items: [Item]) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.utcOffset = utcOffset
        self.timeZone = timeZone
        self.participants = participants
        self.researcher = researcher
        self.device = device
        self.startLocation = startLocation
        self.spans = spans
        self.items = items
    }
}
