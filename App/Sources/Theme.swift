import SwiftUI
import UIKit

/// Colours and type, taken from the approved mockups. The dark colours are the same palette turned
/// over, for use in a dim room.
enum Theme {
    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> UIColor {
        func color(_ hex: UInt32) -> UIColor {
            UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return UIColor { traits in traits.userInterfaceStyle == .dark ? color(dark) : color(light) }
    }

    static let inkUI = dynamic(0x1C1B19, 0xF1EFE9)
    static let secondaryUI = dynamic(0x5F5B52, 0xB3AEA4)

    static let ink = Color(uiColor: inkUI)
    static let secondary = Color(uiColor: secondaryUI)
    static let rule = Color(uiColor: dynamic(0xE2DFD7, 0x3A3832))
    static let outline = Color(uiColor: dynamic(0x858177, 0x8E897F))
    static let recording = Color(uiColor: dynamic(0x9A2B1F, 0xE8796A))
    /// The red behind white words in a warning line; dark enough for white in both appearances.
    static let alarm = Color(uiColor: dynamic(0x9A2B1F, 0x8A2A1F))
    static let accent = Color(uiColor: dynamic(0x1F5E63, 0x86C5CA))
    static let accentWash = Color(uiColor: dynamic(0xE6EFEE, 0x1E3436))
    static let paper = Color(uiColor: dynamic(0xFFFFFF, 0x161513))
    static let strip = Color(uiColor: dynamic(0xFBFAF7, 0x1F1E1B))
    static let pill = Color(uiColor: dynamic(0xF1EFE9, 0x2B2A26))
    static let thumbnail = Color(uiColor: dynamic(0xE9E7E1, 0x2B2A26))
    /// The filled Hide button: ink on paper turned over.
    static let onInk = Color(uiColor: dynamic(0xFFFFFF, 0x161513))

    /// A size from the mockups, grown or shrunk with the text size chosen in the phone's settings.
    static func scaled(_ size: CGFloat) -> CGFloat {
        UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
    }

    /// The same, but never more than half as big again: for buttons, bars and labels, which have
    /// to stay on the screen. Notes grow all the way.
    static func scaledChrome(_ size: CGFloat) -> CGFloat {
        min(scaled(size), size * 1.5)
    }

    /// The face notes are set in.
    static func note(_ size: CGFloat) -> Font {
        .system(size: scaled(size), design: .serif)
    }

    /// The face of a session's title: the notes' face, but like the controls it stops growing at
    /// one and a half times, since a title that fills the screen leaves no room for the page.
    static func title(_ size: CGFloat) -> Font {
        .system(size: scaledChrome(size), design: .serif)
    }

    /// The same face for the field notes are typed in.
    static func noteUIFont(_ size: CGFloat) -> UIFont {
        let base = UIFont.systemFont(ofSize: scaled(size))
        guard let serif = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: serif, size: scaled(size))
    }

    /// The face controls and small print are set in.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: scaledChrome(size), weight: weight)
    }
}

/// This version's microphone, camera and location are stand-ins. While that is so, every screen says so.
enum Trial {
    static let isStandIn = true
    static let line = "Trial version. No sound is recorded, photos are stand-ins and nothing is located. Do not use it for a real interview."
}

/// The line that says this is the trial version. Stage 1c removes it together with the stand-ins.
struct TrialBanner: View {
    var body: some View {
        if Trial.isStandIn {
            Text(Trial.line)
                .font(Theme.ui(12, .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                // Kept to its own strip: it must not colour the status bar or a title above it.
                .background(Theme.alarm, ignoresSafeAreaEdges: [])
                .accessibilityIdentifier("trial-banner")
        }
    }
}
