import Foundation

/// Time-ordered unique ids: 48 bits of Unix milliseconds, then version 7, then random bits.
public enum UUIDv7 {
    /// `randomA` uses its low 12 bits; `randomB` its low 62 bits.
    public static func make(at instant: Instant, randomA: UInt16, randomB: UInt64) -> String {
        let time = UInt64(truncatingIfNeeded: instant.millisecondsSince1970) & 0xFFFF_FFFF_FFFF
        let a = UInt64(randomA & 0x0FFF)
        let b = randomB & 0x3FFF_FFFF_FFFF_FFFF

        let timeHigh = time >> 16                       // 32 bits
        let timeLow = time & 0xFFFF                     // 16 bits
        let versionAndA = 0x7000 | a                    // 16 bits
        let variantAndB = 0x8000 | (b >> 48)            // 16 bits: "10" then the top 14 bits of b
        let node = b & 0xFFFF_FFFF_FFFF                 // 48 bits

        return hex(timeHigh, 8) + "-" + hex(timeLow, 4) + "-" + hex(versionAndA, 4) + "-"
            + hex(variantAndB, 4) + "-" + hex(node, 12)
    }

    /// Lower-case, hyphenated, version 7, variant 10.
    public static func isValid(_ string: String) -> Bool {
        let bytes = Array(string.utf8)
        guard bytes.count == 36 else { return false }
        for (index, byte) in bytes.enumerated() {
            switch index {
            case 8, 13, 18, 23:
                guard byte == 45 else { return false }                                   // "-"
            case 14:
                guard byte == 55 else { return false }                                   // "7"
            case 19:
                guard byte == 56 || byte == 57 || byte == 97 || byte == 98 else { return false }   // 8 9 a b
            default:
                guard (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102) else { return false }
            }
        }
        return true
    }

    /// The last 4 characters, used in folder names.
    public static func shortId(_ id: String) -> String {
        String(id.suffix(4))
    }

    private static func hex(_ value: UInt64, _ width: Int) -> String {
        let text = String(value, radix: 16)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

/// Where new ids come from. Injected so that tests and the worked example are repeatable.
public protocol IdSource: Sendable {
    mutating func next(at instant: Instant) -> String
}

/// Ids from the system's random number generator. This is what the app uses.
public struct RandomIdSource: IdSource {
    public init() {}

    public mutating func next(at instant: Instant) -> String {
        var generator = SystemRandomNumberGenerator()
        return UUIDv7.make(at: instant,
                           randomA: UInt16.random(in: .min ... .max, using: &generator),
                           randomB: UInt64.random(in: .min ... .max, using: &generator))
    }
}

/// Repeatable ids: the same seed always gives the same sequence. For tests and examples only.
public struct SeededIdSource: IdSource {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next(at instant: Instant) -> String {
        let a = nextRandom()
        let b = nextRandom()
        return UUIDv7.make(at: instant, randomA: UInt16(truncatingIfNeeded: a), randomB: b)
    }

    /// SplitMix64.
    private mutating func nextRandom() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
