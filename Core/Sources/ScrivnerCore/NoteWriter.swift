import Foundation

/// Turns what the owner types into notes on the timeline.
///
/// A note begins at its first character that is not blank space, which is the time it keeps. It
/// ends when the owner starts a new paragraph or moves away (`finish`). A note with nothing in it
/// never stays on the page.
public struct NoteWriter: Sendable {
    /// The note being written, if one has been started.
    public private(set) var openNoteId: String?

    public init() {}

    private static func isBlank(_ text: String) -> Bool {
        text.allSatisfy { $0.isWhitespace }
    }

    private static func isNote(_ id: String, in timeline: SessionTimeline) -> Bool {
        timeline.manifest.items.contains { item in
            if case .text(let placement, _, _) = item { return placement.id == id }
            return false
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The text of the note being written is now `text`. Blank space at the ends is kept while writing.
    public mutating func typing(_ text: String, at moment: Moment, in timeline: inout SessionTimeline) throws {
        // The open note may have been removed by another route (emptied as an older note would be).
        if let open = openNoteId, !Self.isNote(open, in: timeline) {
            openNoteId = nil
        }
        if let open = openNoteId {
            if Self.isBlank(text) {
                // Everything was deleted: the note goes, and typing again starts a fresh one with a fresh time.
                try timeline.removeItem(id: open)
                openNoteId = nil
            } else {
                try timeline.setText(id: open, text: text)
            }
        } else if !Self.isBlank(text) {
            openNoteId = try timeline.addText(text, at: moment)
        }
    }

    /// The owner started a new paragraph or moved away. The note's ends are trimmed of blank space.
    public mutating func finish(in timeline: inout SessionTimeline) throws {
        guard let open = openNoteId else { return }
        openNoteId = nil
        for item in timeline.manifest.items {
            if case .text(let placement, let text, _) = item, placement.id == open {
                let tidy = Self.trimmed(text)
                if tidy.isEmpty {
                    try timeline.removeItem(id: open)
                } else if tidy != text {
                    try timeline.setText(id: open, text: tidy)
                }
                return
            }
        }
    }

    /// The owner changed an older note. Blank text removes it. Otherwise it keeps its time and its
    /// place on the audio, and records when it was changed. Text that is the same as before changes nothing.
    public func revise(id: String, text: String, at moment: Moment, in timeline: inout SessionTimeline) throws {
        // Only notes can be revised: an id that names a photo or a marker is not found.
        guard Self.isNote(id, in: timeline) else { throw TimelineError.noSuchItem(id) }
        let tidy = Self.trimmed(text)
        guard !tidy.isEmpty else {
            try timeline.removeItem(id: id)
            return
        }
        for item in timeline.manifest.items {
            if case .text(let placement, let current, _) = item, placement.id == id, current == tidy {
                return
            }
        }
        try timeline.editText(id: id, text: tidy, at: moment)
    }
}
