import SwiftUI

/// Colours and type, taken from the approved mockups.
enum Theme {
    static let ink = Color(red: 0x1C / 255, green: 0x1B / 255, blue: 0x19 / 255)
    static let secondary = Color(red: 0x5F / 255, green: 0x5B / 255, blue: 0x52 / 255)
    static let rule = Color(red: 0xE2 / 255, green: 0xDF / 255, blue: 0xD7 / 255)
    static let outline = Color(red: 0x85 / 255, green: 0x81 / 255, blue: 0x77 / 255)
    static let recording = Color(red: 0x9A / 255, green: 0x2B / 255, blue: 0x1F / 255)
    static let accent = Color(red: 0x1F / 255, green: 0x5E / 255, blue: 0x63 / 255)
    static let accentWash = Color(red: 0xE6 / 255, green: 0xEF / 255, blue: 0xEE / 255)
    static let paper = Color.white
    static let strip = Color(red: 0xFB / 255, green: 0xFA / 255, blue: 0xF7 / 255)
    static let pill = Color(red: 0xF1 / 255, green: 0xEF / 255, blue: 0xE9 / 255)
    static let thumbnail = Color(red: 0xE9 / 255, green: 0xE7 / 255, blue: 0xE1 / 255)

    /// The face notes are set in.
    static func note(_ size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
}
