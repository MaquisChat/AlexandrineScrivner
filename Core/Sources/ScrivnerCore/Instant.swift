import Foundation

// Calendar arithmetic is done by hand so that results never depend on the machine's locale or
// time zone. The two functions below are the standard days-from-civil algorithms.

private func daysFromCivil(year: Int64, month: Int64, day: Int64) -> Int64 {
    let y = month <= 2 ? year - 1 : year
    let era = (y >= 0 ? y : y - 399) / 400
    let yearOfEra = y - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}

private func civilFromDays(_ days: Int64) -> (year: Int64, month: Int64, day: Int64) {
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let dayOfEra = z - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthPart = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthPart + 2) / 5 + 1
    let month = monthPart < 10 ? monthPart + 3 : monthPart - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (year, month, day)
}

private func daysInMonth(year: Int64, month: Int64) -> Int64 {
    switch month {
    case 1, 3, 5, 7, 8, 10, 12: return 31
    case 4, 6, 9, 11: return 30
    default:
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        return leap ? 29 : 28
    }
}

/// Floor division and the matching non-negative remainder.
private func floorDivMod(_ value: Int64, _ divisor: Int64) -> (quotient: Int64, remainder: Int64) {
    var quotient = value / divisor
    var remainder = value % divisor
    if remainder < 0 {
        quotient -= 1
        remainder += divisor
    }
    return (quotient, remainder)
}

private func padded(_ value: Int64, _ width: Int) -> String {
    let text = String(value)
    return String(repeating: "0", count: max(0, width - text.count)) + text
}

/// The fields of a UTC millisecond count.
private func fields(ofMilliseconds ms: Int64) -> (year: Int64, month: Int64, day: Int64, hour: Int64, minute: Int64, second: Int64, millisecond: Int64) {
    let (days, msOfDay) = floorDivMod(ms, 86_400_000)
    let date = civilFromDays(days)
    return (date.year, date.month, date.day,
            msOfDay / 3_600_000, (msOfDay / 60_000) % 60, (msOfDay / 1000) % 60, msOfDay % 1000)
}

/// A moment in time, kept as whole milliseconds since 1970 in UTC.
public struct Instant: Hashable, Comparable, Sendable {
    public let millisecondsSince1970: Int64

    public init(millisecondsSince1970: Int64) {
        self.millisecondsSince1970 = millisecondsSince1970
    }

    /// Rounded to the nearest millisecond.
    public init(date: Date) {
        self.millisecondsSince1970 = Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// Accepts exactly "YYYY-MM-DDTHH:MM:SS.mmmZ".
    public init?(iso: String) {
        let bytes = Array(iso.utf8)
        guard bytes.count == 24 else { return nil }
        func number(_ range: Range<Int>) -> Int64? {
            var value: Int64 = 0
            for index in range {
                let byte = bytes[index]
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int64(byte - 48)
            }
            return value
        }
        func isByte(_ index: Int, _ character: Character) -> Bool {
            bytes[index] == character.asciiValue
        }
        guard isByte(4, "-"), isByte(7, "-"), isByte(10, "T"), isByte(13, ":"), isByte(16, ":"),
              isByte(19, "."), isByte(23, "Z"),
              let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              let millisecond = number(20..<23),
              (1...12).contains(month), day >= 1, day <= daysInMonth(year: year, month: month),
              hour <= 23, minute <= 59, second <= 59 else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        self.millisecondsSince1970 = days * 86_400_000 + hour * 3_600_000 + minute * 60_000 + second * 1000 + millisecond
    }

    public var iso: String {
        let f = fields(ofMilliseconds: millisecondsSince1970)
        return "\(padded(f.year, 4))-\(padded(f.month, 2))-\(padded(f.day, 2))T"
            + "\(padded(f.hour, 2)):\(padded(f.minute, 2)):\(padded(f.second, 2)).\(padded(f.millisecond, 3))Z"
    }

    public func adding(milliseconds: Int64) -> Instant {
        Instant(millisecondsSince1970: millisecondsSince1970 + milliseconds)
    }

    public static func < (lhs: Instant, rhs: Instant) -> Bool {
        lhs.millisecondsSince1970 < rhs.millisecondsSince1970
    }
}

/// How far local time is from UTC, in seconds east.
public struct UTCOffset: Hashable, Sendable {
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }

    /// Accepts "+HH:MM" or "-HH:MM", from -18:00 to +18:00.
    public init?(string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 6, bytes[3] == 58 /* : */ else { return nil }
        let sign: Int
        switch bytes[0] {
        case 43: sign = 1      // +
        case 45: sign = -1     // -
        default: return nil
        }
        func digit(_ index: Int) -> Int? {
            let byte = bytes[index]
            return (byte >= 48 && byte <= 57) ? Int(byte - 48) : nil
        }
        guard let h1 = digit(1), let h2 = digit(2), let m1 = digit(4), let m2 = digit(5) else { return nil }
        let hours = h1 * 10 + h2
        let minutes = m1 * 10 + m2
        guard minutes <= 59, hours <= 18, !(hours == 18 && minutes != 0) else { return nil }
        self.seconds = sign * (hours * 3600 + minutes * 60)
    }

    public var string: String {
        let magnitude = abs(seconds)
        let sign = seconds < 0 ? "-" : "+"
        return "\(sign)\(padded(Int64(magnitude / 3600), 2)):\(padded(Int64((magnitude % 3600) / 60), 2))"
    }
}

/// An instant as a clock on the wall would show it at a given offset.
public struct LocalClock: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int
    public let minute: Int
    public let second: Int

    public init(_ instant: Instant, offset: UTCOffset) {
        let f = fields(ofMilliseconds: instant.millisecondsSince1970 + Int64(offset.seconds) * 1000)
        year = Int(f.year)
        month = Int(f.month)
        day = Int(f.day)
        hour = Int(f.hour)
        minute = Int(f.minute)
        second = Int(f.second)
    }
}
