import Foundation

/// One thing on the page, ready to draw.
public struct PageRow: Equatable, Sendable, Identifiable {
    public enum Content: Equatable, Sendable {
        /// Ready to show, for example `Recording started · local time, UTC+5:45`.
        case marker(String)
        case text(String, edited: Bool)
        case photo(file: String)
        /// `note` says anything worth knowing about the clip: `no sound`, `still recording`, why it ended.
        case video(file: String, length: String?, note: String?)
        case ink(file: String)
    }

    public let id: String
    /// The clock time to show beside it or under it: local time where and when it was made.
    public let time: String
    public let content: Content
    /// False when it was made while nothing was recording.
    public let isOnAudio: Bool

    public init(id: String, time: String, content: Content, isOnAudio: Bool) {
        self.id = id
        self.time = time
        self.content = content
        self.isOnAudio = isOnAudio
    }
}

/// A session as its page shows it: the same rows whichever of the two layouts draws them.
public struct Page: Equatable, Sendable {
    public let title: String
    public let rows: [PageRow]

    public init(_ manifest: Manifest, style: ClockStyle) {
        title = manifest.displayTitle
        rows = manifest.items.map { item in
            let placement = item.placement
            let content: PageRow.Content
            switch item {
            case .marker(_, let type, let detail):
                content = .marker(Self.markerLine(type, detail, placement.utcOffset))
            case .text(_, let text, let modifiedAt):
                content = .text(text, edited: modifiedAt != nil)
            case .photo(_, let file, _, _):
                content = .photo(file: file)
            case .video(_, let durationMs, let endedBy, let sound, let file, _, _):
                content = .video(file: file, length: durationMs.map(Wording.length(milliseconds:)),
                                 note: Self.clipNote(endedBy: endedBy, sound: sound))
            case .ink(_, _, let file, _, _, _, _):
                content = .ink(file: file)
            }
            return PageRow(id: placement.id, time: Wording.clock(placement.at, offset: placement.utcOffset, style: style),
                           content: content, isOnAudio: placement.spanId != nil)
        }
    }

    /// Markers about recording also say which clock the times on the page are on (spec 5.3).
    private static func markerLine(_ type: MarkerType, _ detail: String?, _ offset: UTCOffset) -> String {
        let words = Wording.marker(type, detail: detail)
        switch type {
        case .recordingStarted, .paused, .resumed, .stopped, .interrupted:
            return "\(words) · local time, \(Wording.zone(offset))"
        case .locationOff, .locationOn:
            return words
        }
    }

    private static func clipNote(endedBy: ClipEnd?, sound: Bool) -> String? {
        var parts: [String] = []
        if !sound { parts.append("no sound") }
        switch endedBy {
        case nil: parts.append("still recording")
        case .user?: break
        case .background?: parts.append("ended when the app left the screen")
        case .lock?: parts.append("ended when the phone locked")
        case .interruption?: parts.append("ended by an interruption")
        case .stop?: parts.append("ended when the session stopped")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
