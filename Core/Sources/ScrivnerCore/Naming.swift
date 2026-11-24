import Foundation

/// Names that are safe on macOS, Windows and Linux, following the workbench's own rules.
public enum Naming {
    /// The longest a session folder name may be, in UTF-8 bytes.
    public static let maxBytes = 150

    private static let forbidden: Set<Unicode.Scalar> = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]

    private static let reserved: Set<String> = {
        var names: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for number in 1...9 {
            names.insert("COM\(number)")
            names.insert("LPT\(number)")
        }
        return names
    }()

    /// Cleans one name. May return an empty string.
    public static func sanitize(_ text: String) -> String {
        // 1. One canonical spelling for accented letters.
        let normalized = text.precomposedStringWithCanonicalMapping

        // 2. Characters no file system accepts everywhere, and control characters, become "-".
        var replaced = String.UnicodeScalarView()
        for scalar in normalized.unicodeScalars {
            if forbidden.contains(scalar) || scalar.properties.generalCategory == .control {
                replaced.append("-")
            } else {
                replaced.append(scalar)
            }
        }

        // 3. Runs of spaces collapse to one.
        var collapsed = ""
        var lastWasSpace = false
        for character in String(replaced) {
            if character.isWhitespace {
                if !lastWasSpace { collapsed.append(" ") }
                lastWasSpace = true
            } else {
                collapsed.append(character)
                lastWasSpace = false
            }
        }

        // 4. No leading or trailing spaces or dots.
        var trimmed = Substring(collapsed)
        while let first = trimmed.first, first == " " || first == "." { trimmed = trimmed.dropFirst() }
        while let last = trimmed.last, last == " " || last == "." { trimmed = trimmed.dropLast() }
        var result = String(trimmed)

        // 5. Names Windows reserves, with or without an extension, get a "_" in front.
        let stem = result.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? result
        if reserved.contains(stem.trimmingCharacters(in: .whitespaces).uppercased()) {
            result = "_" + result
        }
        return result
    }

    /// `<date> <start time> <title> [<4-character id>]`, at most `maxBytes` long.
    public static func sessionFolderName(createdAt: Instant, utcOffset: UTCOffset, title: String, sessionId: String) -> String {
        let clock = LocalClock(createdAt, offset: utcOffset)
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        let year = String(repeating: "0", count: max(0, 4 - String(clock.year).count)) + String(clock.year)
        let head = "\(year)-\(two(clock.month))-\(two(clock.day)) \(two(clock.hour))\(two(clock.minute))"
        let tail = " [\(UUIDv7.shortId(sessionId))]"

        let cleanTitle = sanitize(title)
        if cleanTitle.isEmpty {
            return head + tail
        }
        let whole = head + " " + cleanTitle + tail
        if whole.utf8.count <= maxBytes {
            return whole
        }

        // Too long: drop whole characters from the end of the title until it fits with "…".
        var shortened = Substring(cleanTitle)
        while !shortened.isEmpty {
            shortened = shortened.dropLast()
            while let last = shortened.last, last == " " || last == "." { shortened = shortened.dropLast() }
            let candidate = head + " " + shortened + "…" + tail
            if candidate.utf8.count <= maxBytes {
                return shortened.isEmpty ? head + tail : candidate
            }
        }
        return head + tail
    }
}
