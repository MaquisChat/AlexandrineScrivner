import Foundation

/// `notes.md`: the page as plain text with clock times, for a person to read.
/// Nothing reads it back; `session.json` is the record.
public enum NotesMarkdown {
    public static func render(_ manifest: Manifest) -> String {
        var paragraphs: [String] = []

        paragraphs.append("# \(manifest.title)")

        let created = LocalClock(manifest.createdAt, offset: manifest.utcOffset)
        var header = "Started \(four(created.year))-\(two(created.month))-\(two(created.day)) "
            + "\(two(created.hour)):\(two(created.minute)) (UTC\(manifest.utcOffset.string), \(manifest.timeZone))"
        if !manifest.participants.isEmpty {
            header += "\nParticipants: " + manifest.participants.joined(separator: ", ")
        }
        paragraphs.append(header)

        for item in manifest.items {
            let placement = item.placement
            let clock = LocalClock(placement.at, offset: placement.utcOffset)
            let time = "**\(two(clock.hour)):\(two(clock.minute))**"
            switch item {
            case .text(_, let text, _):
                paragraphs.append("\(time) \(text)")
            case .marker(_, let type, let detail):
                paragraphs.append("\(time) *\(Wording.marker(type, detail: detail))*")
            case .photo(_, let file, _, _):
                paragraphs.append("\(time) [photo: \(file)]")
            case .video(_, let durationMs, _, let sound, let file, _, _):
                var note = "[video: \(file)"
                if let durationMs {
                    note += ", " + Wording.length(milliseconds: durationMs)
                }
                if !sound { note += ", no sound" }
                paragraphs.append("\(time) \(note)]")
            case .ink(_, _, let file, _, _, _, _):
                paragraphs.append("\(time) [handwriting: \(file)]")
            }
        }

        return paragraphs.joined(separator: "\n\n") + "\n"
    }

    private static func two(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    private static func four(_ value: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, 4 - text.count)) + text
    }
}
