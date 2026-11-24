import Foundation

/// A date and time as ExifTool prints it: `YYYY:MM:DD HH:MM:SS`, optionally with a fraction of a
/// second, optionally followed by `Z` or an offset from UTC such as `+05:45`.
public struct ExifDate: Equatable, Sendable {
    /// The clock reading, held as if it were UTC.
    public let local: Instant
    /// The offset from UTC the file states, if it states one.
    public let offset: UTCOffset?
    /// Whether the text carried a fraction of a second.
    public let hasFraction: Bool

    /// The true moment: the clock reading minus the offset. Nil when no offset is stated.
    public var instant: Instant? {
        offset.map { local.adding(milliseconds: -Int64($0.seconds) * 1000) }
    }

    public init(local: Instant, offset: UTCOffset?, hasFraction: Bool) {
        self.local = local
        self.offset = offset
        self.hasFraction = hasFraction
    }

    /// Nil for anything that is not a real date in the form above, including the all-zero date
    /// some cameras write when their clock was never set.
    public init?(_ text: String) {
        let bytes = Array(text.utf8)
        guard bytes.count >= 19 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        func isByte(_ index: Int, _ character: Character) -> Bool {
            bytes[index] == character.asciiValue
        }
        guard isByte(4, ":"), isByte(7, ":"), isByte(10, " "), isByte(13, ":"), isByte(16, ":"),
              let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              year != 0 else { return nil }

        var position = 19
        var millisecond = 0
        var fraction = false
        if position < bytes.count, isByte(position, ".") {
            position += 1
            let start = position
            while position < bytes.count, bytes[position] >= 48, bytes[position] <= 57 { position += 1 }
            let digits = position - start
            guard (1...6).contains(digits) else { return nil }
            // Cut to milliseconds: the first three digits, padded on the right.
            for index in 0..<3 {
                millisecond = millisecond * 10 + (index < digits ? Int(bytes[start + index] - 48) : 0)
            }
            fraction = true
        }

        var stated: UTCOffset?
        if position < bytes.count {
            let rest = String(decoding: bytes[position...], as: UTF8.self)
            if rest == "Z" {
                stated = UTCOffset(seconds: 0)
            } else if let parsed = UTCOffset(string: rest) {
                stated = parsed
            } else {
                return nil
            }
        }

        guard let reading = Instant(year: year, month: month, day: day, hour: hour, minute: minute,
                                    second: second, millisecond: millisecond) else { return nil }
        self.local = reading
        self.offset = stated
        self.hasFraction = fraction
    }
}
