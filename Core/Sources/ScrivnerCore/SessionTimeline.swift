import Foundation

/// One moment as the device saw it: the monotonic clock audio is stamped on, the wall clock,
/// and the time zone in force.
public struct Moment: Equatable, Sendable {
    /// Monotonic seconds. Differences between two moments are trustworthy even if the wall clock is changed.
    public var host: Double
    public var wall: Instant
    public var utcOffset: UTCOffset
    public var timeZone: String

    public init(host: Double, wall: Instant, utcOffset: UTCOffset, timeZone: String) {
        self.host = host
        self.wall = wall
        self.utcOffset = utcOffset
        self.timeZone = timeZone
    }
}

public enum TimelineError: Error, Equatable {
    case alreadyRecording
    case notRecording
    case needsRecovery
    case noSuchItem(String)
    case clipAlreadyEnded(String)
}

/// Keeps a session's manifest as things happen: opens and closes recording spans, and gives every
/// note, photo and clip its instant and its position on the audio.
///
/// Positions come from the monotonic clock (`Moment.host`), never from subtracting wall-clock times.
public struct SessionTimeline: Sendable {
    public private(set) var manifest: Manifest
    /// True after resuming a manifest that was cut off mid-recording or mid-clip.
    /// Until `recoverAfterCrash` is called, nothing new can be added.
    public private(set) var needsRecovery: Bool

    private var ids: any IdSource
    private var openSpanHostStart: Double?
    private var openClipHostStarts: [String: Double] = [:]
    private var hasRecorded: Bool

    public var isRecording: Bool { openSpanHostStart != nil }

    public init(title: String, participants: [String], researcher: String?, device: DeviceInfo,
                startLocation: GeoPoint?, at moment: Moment, ids: any IdSource) {
        var source = ids
        let id = source.next(at: moment.wall)
        self.ids = source
        self.manifest = Manifest(id: id, title: title, createdAt: moment.wall, utcOffset: moment.utcOffset,
                                 timeZone: moment.timeZone, participants: participants, researcher: researcher,
                                 device: device, startLocation: startLocation, spans: [], items: [])
        self.needsRecovery = false
        self.hasRecorded = false
    }

    public init(resuming manifest: Manifest, ids: any IdSource) {
        self.manifest = manifest
        self.ids = ids
        self.hasRecorded = !manifest.spans.isEmpty
        let openSpan = manifest.spans.contains { $0.endedBy == nil }
        let openClip = manifest.items.contains { item in
            if case .video(_, _, let endedBy, _, _, _, _) = item { return endedBy == nil }
            return false
        }
        self.needsRecovery = openSpan || openClip
    }

    // MARK: - Session details

    public mutating func setTitle(_ title: String) {
        manifest.title = title
    }

    public mutating func setParticipants(_ participants: [String]) {
        manifest.participants = participants
    }

    // MARK: - Recording

    /// Opens a new span. Returns its id.
    @discardableResult
    public mutating func startRecording(file: String, at moment: Moment) throws -> String {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        guard !isRecording else { throw TimelineError.alreadyRecording }
        let spanId = ids.next(at: moment.wall)
        manifest.spans.append(Span(id: spanId, file: file, sha256: nil, startedAt: moment.wall,
                                   utcOffset: moment.utcOffset, timeZone: moment.timeZone,
                                   durationMs: nil, endedBy: nil))
        openSpanHostStart = moment.host
        let type: MarkerType = hasRecorded ? .resumed : .recordingStarted
        hasRecorded = true
        manifest.items.append(.marker(place(at: moment), type: type, detail: nil))
        return spanId
    }

    /// Closes the open span. `audioDurationMs` is the audio file's own length when it is known.
    public mutating func endRecording(by end: SpanEnd, detail: String? = nil, audioDurationMs: Int? = nil,
                                      at moment: Moment) throws {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        guard let start = openSpanHostStart, let index = manifest.spans.indices.last else {
            throw TimelineError.notRecording
        }
        let duration = max(0, audioDurationMs ?? Self.milliseconds(from: start, to: moment.host))

        // The closing marker sits on the span it closes, never past the span's end.
        var placement = place(at: moment)
        if let offset = placement.offsetMs {
            placement.offsetMs = min(offset, duration)
        }
        let type: MarkerType
        var markerDetail = detail
        switch end {
        case .pause: type = .paused
        case .stop: type = .stopped
        case .interruption: type = .interrupted
        case .crashRecovered:
            type = .interrupted
            markerDetail = detail ?? "crash-recovered"
        }
        manifest.items.append(.marker(placement, type: type, detail: markerDetail))

        manifest.spans[index].durationMs = duration
        manifest.spans[index].endedBy = end
        openSpanHostStart = nil
    }

    /// After the app was cut off: closes what was left open and notes the interruption.
    /// `spanDurationMs` is how much of the open span's audio can be read; nil counts as none.
    public mutating func recoverAfterCrash(spanDurationMs: Int?, at moment: Moment) {
        for index in manifest.spans.indices where manifest.spans[index].endedBy == nil {
            manifest.spans[index].durationMs = max(0, spanDurationMs ?? 0)
            manifest.spans[index].endedBy = .crashRecovered
        }
        for index in manifest.items.indices {
            if case .video(let p, let durationMs, nil, let sound, let file, let sha256, let gps) = manifest.items[index] {
                manifest.items[index] = .video(p, durationMs: durationMs, endedBy: .interruption, sound: sound,
                                               file: file, sha256: sha256, gps: gps)
            }
        }
        openSpanHostStart = nil
        openClipHostStarts.removeAll()
        needsRecovery = false
        manifest.items.append(.marker(place(at: moment), type: .interrupted, detail: "crash-recovered"))
    }

    // MARK: - Items

    @discardableResult
    public mutating func addText(_ text: String, at moment: Moment) throws -> String {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        let placement = place(at: moment)
        manifest.items.append(.text(placement, text: text, modifiedAt: nil))
        return placement.id
    }

    /// Changes a note's words. The note keeps its original time and place on the audio.
    public mutating func editText(id: String, text: String, at moment: Moment) throws {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        for index in manifest.items.indices {
            if case .text(let p, _, _) = manifest.items[index], p.id == id {
                manifest.items[index] = .text(p, text: text, modifiedAt: moment.wall)
                return
            }
        }
        throw TimelineError.noSuchItem(id)
    }

    @discardableResult
    public mutating func addPhoto(file: String, gps: GeoPoint?, at moment: Moment) throws -> String {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        let placement = place(at: moment)
        manifest.items.append(.photo(placement, file: file, sha256: nil, gps: gps))
        return placement.id
    }

    /// Starts a clip. It has sound only if audio is being recorded at this moment.
    @discardableResult
    public mutating func startClip(file: String, gps: GeoPoint?, at moment: Moment) throws -> String {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        let placement = place(at: moment)
        manifest.items.append(.video(placement, durationMs: nil, endedBy: nil, sound: isRecording,
                                     file: file, sha256: nil, gps: gps))
        openClipHostStarts[placement.id] = moment.host
        return placement.id
    }

    public mutating func endClip(id: String, by end: ClipEnd, at moment: Moment) throws {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        for index in manifest.items.indices {
            if case .video(let p, _, let endedBy, let sound, let file, let sha256, let gps) = manifest.items[index], p.id == id {
                guard endedBy == nil else { throw TimelineError.clipAlreadyEnded(id) }
                let duration = openClipHostStarts[id].map { max(0, Self.milliseconds(from: $0, to: moment.host)) }
                manifest.items[index] = .video(p, durationMs: duration, endedBy: end, sound: sound,
                                               file: file, sha256: sha256, gps: gps)
                openClipHostStarts[id] = nil
                return
            }
        }
        throw TimelineError.noSuchItem(id)
    }

    /// Notes on the page that location was switched off or on.
    public mutating func setLocation(enabled: Bool, at moment: Moment) throws {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        manifest.items.append(.marker(place(at: moment), type: enabled ? .locationOn : .locationOff, detail: nil))
    }

    // MARK: - Placing

    private static func milliseconds(from start: Double, to end: Double) -> Int {
        Int(((end - start) * 1000).rounded())
    }

    /// A new item's id, instant and, while recording, its position on the open span.
    private mutating func place(at moment: Moment) -> Placement {
        let id = ids.next(at: moment.wall)
        if let start = openSpanHostStart, let span = manifest.spans.last {
            let offset = max(0, Self.milliseconds(from: start, to: moment.host))
            return Placement(id: id, at: moment.wall, utcOffset: moment.utcOffset, spanId: span.id, offsetMs: offset)
        }
        return Placement(id: id, at: moment.wall, utcOffset: moment.utcOffset, spanId: nil, offsetMs: nil)
    }
}
