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
    case nothingToRecover
    case cannotRemoveMarker
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
    /// When each span made in this run began and ended on the monotonic clock. Lets something that
    /// reports late (a photo still being written when recording paused) be placed on the span that
    /// was open at the moment it was made. Empty for spans loaded from disk.
    private var spanHostRanges: [(spanId: String, start: Double, end: Double?)] = []
    private var openClipHostStarts: [String: Double] = [:]
    private var hasRecorded: Bool

    public var isRecording: Bool { openSpanHostStart != nil }

    /// The span being recorded, if any.
    public var openSpanId: String? { isRecording ? manifest.spans.last?.id : nil }

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

    public mutating func setResearcher(_ researcher: String?) {
        manifest.researcher = researcher
    }

    /// Where the session began. Recording starts at once and the first location fix usually
    /// arrives a few seconds later, so this can be set at any time.
    public mutating func setStartLocation(_ location: GeoPoint?) {
        manifest.startLocation = location
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
        spanHostRanges.append((spanId, moment.host, nil))
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
        // The closing marker sits on the span it closes.
        let placement = place(at: moment)
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

        closeSpan(at: index, by: end,
                  durationMs: audioDurationMs ?? Self.milliseconds(from: start, to: moment.host))
        openSpanHostStart = nil
        if let last = spanHostRanges.indices.last, spanHostRanges[last].end == nil {
            spanHostRanges[last].end = moment.host
        }
    }

    /// How long the open span has been recording, by the monotonic clock. Nil when nothing is recording.
    public func openSpanElapsedMs(at moment: Moment) -> Int? {
        openSpanHostStart.map { max(0, Self.milliseconds(from: $0, to: moment.host)) }
    }

    /// Writes a marker on the page that no other call writes: the end of a session that was paused
    /// when it was stopped, or an interruption that left nothing open to close.
    public mutating func addMarker(_ type: MarkerType, detail: String? = nil, at moment: Moment) throws {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        manifest.items.append(.marker(place(at: moment), type: type, detail: detail))
    }

    // MARK: - Checksums

    /// Sets the checksum of every listed file that `sums` has, by its path.
    public mutating func setChecksums(_ sums: [String: String]) {
        for index in manifest.spans.indices {
            if let sum = sums[manifest.spans[index].file] { manifest.spans[index].sha256 = sum }
        }
        for index in manifest.items.indices {
            switch manifest.items[index] {
            case .photo(let p, let file, let sha256, let gps):
                manifest.items[index] = .photo(p, file: file, sha256: sums[file] ?? sha256, gps: gps)
            case .video(let p, let durationMs, let endedBy, let sound, let file, let sha256, let gps):
                manifest.items[index] = .video(p, durationMs: durationMs, endedBy: endedBy, sound: sound, file: file,
                                               sha256: sums[file] ?? sha256, gps: gps)
            case .ink(let p, let endAt, let file, let sha256, let data, let dataSha256, let strokes):
                manifest.items[index] = .ink(p, endAt: endAt, file: file, sha256: sums[file] ?? sha256, data: data,
                                             dataSha256: sums[data] ?? dataSha256, strokes: strokes)
            case .marker, .text:
                break
            }
        }
    }

    /// Removes every checksum: the session is being added to again, and a checksum must never
    /// sit beside a file that may have changed.
    public mutating func clearChecksums() {
        for index in manifest.spans.indices { manifest.spans[index].sha256 = nil }
        for index in manifest.items.indices {
            switch manifest.items[index] {
            case .photo(let p, let file, _, let gps):
                manifest.items[index] = .photo(p, file: file, sha256: nil, gps: gps)
            case .video(let p, let durationMs, let endedBy, let sound, let file, _, let gps):
                manifest.items[index] = .video(p, durationMs: durationMs, endedBy: endedBy, sound: sound, file: file, sha256: nil, gps: gps)
            case .ink(let p, let endAt, let file, _, let data, _, let strokes):
                manifest.items[index] = .ink(p, endAt: endAt, file: file, sha256: nil, data: data, dataSha256: nil, strokes: strokes)
            case .marker, .text:
                break
            }
        }
    }

    /// After the app was cut off: closes what was left open and notes the interruption.
    /// `spanDurationMs` is how much of the open span's audio can be read. Nil means the length
    /// could not be read; the span is then taken to be as long as the last thing placed on it.
    /// Throws `nothingToRecover` unless `needsRecovery` is true, so a healthy recording is never closed by mistake.
    public mutating func recoverAfterCrash(spanDurationMs: Int?, at moment: Moment) throws {
        guard needsRecovery else { throw TimelineError.nothingToRecover }
        for index in manifest.spans.indices where manifest.spans[index].endedBy == nil {
            closeSpan(at: index, by: .crashRecovered, durationMs: spanDurationMs)
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
        addCrashMarker()
    }

    /// Notes on the page that the app was closed unexpectedly, stamped with the last moment the
    /// session is known to have been alive (its last item, or the end of the audio that was kept),
    /// not with the time it happened to be opened again.
    public mutating func addCrashMarker() {
        var lastKnown = manifest.createdAt
        var offset = manifest.utcOffset
        for item in manifest.items where item.placement.at > lastKnown {
            lastKnown = item.placement.at
            offset = item.placement.utcOffset
        }
        for span in manifest.spans {
            let end = span.startedAt.adding(milliseconds: Int64(span.durationMs ?? 0))
            if end > lastKnown {
                lastKnown = end
                offset = span.utcOffset
            }
        }
        let placement = Placement(id: ids.next(at: lastKnown), at: lastKnown, utcOffset: offset, spanId: nil, offsetMs: nil)
        manifest.items.append(.marker(placement, type: .interrupted, detail: "crash-recovered"))
    }

    /// Takes on a repaired copy of this session's manifest: the same session with things removed
    /// whose files are gone. Only while nothing is being recorded.
    public mutating func adopt(repaired: Manifest) throws {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        guard !isRecording else { throw TimelineError.alreadyRecording }
        guard repaired.id == manifest.id else { throw TimelineError.noSuchItem(repaired.id) }
        manifest = repaired
        let kept = Set(repaired.spans.map(\.id))
        spanHostRanges.removeAll { !kept.contains($0.spanId) }
    }

    // MARK: - Items

    @discardableResult
    public mutating func addText(_ text: String, at moment: Moment) throws -> String {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        let placement = place(at: moment)
        manifest.items.append(.text(placement, text: text, modifiedAt: nil))
        return placement.id
    }

    /// Changes the words of a note that is still being written. Unlike `editText`, this does not
    /// count as a later edit: `modifiedAt` is left as it is.
    public mutating func setText(id: String, text: String) throws {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        for index in manifest.items.indices {
            if case .text(let p, _, let modifiedAt) = manifest.items[index], p.id == id {
                manifest.items[index] = .text(p, text: text, modifiedAt: modifiedAt)
                return
            }
        }
        throw TimelineError.noSuchItem(id)
    }

    /// Takes a note, photo, clip or handwriting block off the page. Markers are the record of what
    /// the recorder did and cannot be removed. The item's files, if any, are the caller's to deal with.
    public mutating func removeItem(id: String) throws {
        guard !needsRecovery else { throw TimelineError.needsRecovery }
        guard let index = manifest.items.firstIndex(where: { $0.placement.id == id }) else {
            throw TimelineError.noSuchItem(id)
        }
        if case .marker = manifest.items[index] {
            throw TimelineError.cannotRemoveMarker
        }
        manifest.items.remove(at: index)
        openClipHostStarts[id] = nil
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

    // MARK: - Closing a span

    /// Closes a span and keeps everything on it inside its audio.
    ///
    /// When the audio's length is known and something was placed after its end (the last moments
    /// of a recording can be lost when the app is cut off), that thing is moved to the end of the
    /// audio; its own time (`at`) is left alone. When the length is not known, the span is as long
    /// as the last thing placed on it.
    private mutating func closeSpan(at index: Int, by end: SpanEnd, durationMs known: Int?) {
        let spanId = manifest.spans[index].id
        var furthest = 0
        for item in manifest.items {
            if item.placement.spanId == spanId, let offset = item.placement.offsetMs {
                furthest = max(furthest, offset)
            }
            if case .ink(_, _, _, _, _, _, let strokes) = item {
                for stroke in strokes where stroke.spanId == spanId {
                    furthest = max(furthest, stroke.offsetMs ?? 0)
                }
            }
        }
        let duration = max(0, known ?? furthest)
        if furthest > duration {
            for itemIndex in manifest.items.indices {
                if manifest.items[itemIndex].placement.spanId == spanId,
                   let offset = manifest.items[itemIndex].placement.offsetMs, offset > duration {
                    manifest.items[itemIndex].placement.offsetMs = duration
                }
                if case .ink(let p, let endAt, let file, let sha256, let data, let dataSha256, var strokes) = manifest.items[itemIndex] {
                    for strokeIndex in strokes.indices where strokes[strokeIndex].spanId == spanId {
                        if let offset = strokes[strokeIndex].offsetMs, offset > duration {
                            strokes[strokeIndex].offsetMs = duration
                        }
                    }
                    manifest.items[itemIndex] = .ink(p, endAt: endAt, file: file, sha256: sha256, data: data,
                                                     dataSha256: dataSha256, strokes: strokes)
                }
            }
        }
        manifest.spans[index].durationMs = duration
        manifest.spans[index].endedBy = end
    }

    // MARK: - Placing

    private static func milliseconds(from start: Double, to end: Double) -> Int {
        Int(((end - start) * 1000).rounded())
    }

    /// A new item's id, instant and its position on the span that was recording at that moment.
    ///
    /// Usually that is the open span. It can also be a span that has since closed, when something
    /// made during it is only reported afterwards; its position is then kept inside the span's audio.
    private mutating func place(at moment: Moment) -> Placement {
        let id = ids.next(at: moment.wall)
        let covering = spanHostRanges.last { range in
            moment.host >= range.start && (range.end.map { moment.host <= $0 } ?? true)
        }
        if let covering, let span = manifest.spans.first(where: { $0.id == covering.spanId }) {
            var offset = max(0, Self.milliseconds(from: covering.start, to: moment.host))
            if let duration = span.durationMs { offset = min(offset, duration) }
            return Placement(id: id, at: moment.wall, utcOffset: moment.utcOffset, spanId: span.id, offsetMs: offset)
        }
        return Placement(id: id, at: moment.wall, utcOffset: moment.utcOffset, spanId: nil, offsetMs: nil)
    }
}
