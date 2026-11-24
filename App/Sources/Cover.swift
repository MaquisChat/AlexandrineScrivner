import SwiftUI
import UIKit

/// Whatever is shown while the page is hidden. A cover draws itself and decides what brings the
/// page back; recording and the page know nothing about it, so another cover can be added later
/// without touching either.
protocol Cover {
    associatedtype Body: View
    @ViewBuilder func body(dismiss: @escaping () -> Void) -> Body
}

/// The cover this version ships: a black screen. Single taps do nothing; a double tap brings the page back.
struct BlankCover: Cover {
    func body(dismiss: @escaping () -> Void) -> some View {
        Color.black
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: dismiss)
            .accessibilityElement()
            .accessibilityLabel("Hidden")
            .accessibilityHint("Double tap to bring the page back")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("cover")
    }
}

/// What the app switcher shows for the app while it is not in front: never the page.
struct PrivacyShade: View {
    var body: some View {
        Color.black
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension View {
    /// Puts the keyboard away, wherever it is.
    func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
