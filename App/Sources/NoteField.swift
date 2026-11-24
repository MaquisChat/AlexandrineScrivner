import SwiftUI
import UIKit

/// The field notes are typed into: a plain text view. Return is taken directly as "this note is
/// finished", so the keyboard stays up between notes and a note is handed over exactly once.
struct NoteField: UIViewRepresentable {
    let text: String
    let font: UIFont
    let color: UIColor
    /// Says when the keyboard is wanted, and is told whether the owner is writing.
    let focus: WritingFocus
    /// Changes whenever the keyboard is asked for, so that the field is looked at again.
    let focusRequest: Int
    let onChange: (String) -> Void
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.font = font
        view.textColor = color
        view.accessibilityIdentifier = "note-field"
        view.accessibilityLabel = "Note"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if focus.handOver {
            focus.handOver = false
            Self.giveKeyboard(to: view)
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        // Never while the keyboard is part-way through composing a character.
        if view.text != text, view.markedTextRange == nil {
            view.text = text
        }
        if view.font != font {
            view.font = font
        }
        view.textColor = color
        if focus.wantsKeyboard {
            focus.wantsKeyboard = false
            Self.giveKeyboard(to: view)
        }
    }

    /// A field that has only just been made is not on screen yet; wait, briefly, until it is.
    static func giveKeyboard(to view: UITextView) {
        Task { @MainActor in
            for _ in 0..<30 {
                // Asked again until it is taken: a box that is on screen can still say no for a
                // moment, while another is giving the keyboard up.
                if view.window != nil, view.becomeFirstResponder() {
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        // Never shorter than a comfortable thing to tap.
        return CGSize(width: width, height: max(fitted.height, 44))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteField

        init(_ parent: NoteField) {
            self.parent = parent
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                // Emptied here and now, so a key pressed straight after Return starts the next
                // note on a clean line rather than on top of the one just finished.
                textView.text = ""
                parent.onReturn()
                return false
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.onChange(textView.text ?? "")
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focus.isWriting = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focus.isWriting = false
        }
    }
}

/// The box an older note is changed in: the whole note, with the cursor at its end and the
/// keyboard already up. Return makes a new line here, as in any text box.
struct EditorField: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    let color: UIColor

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.font = font
        view.textColor = color
        view.text = text
        view.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        view.accessibilityIdentifier = "note-editor"
        view.accessibilityLabel = "Note"
        NoteField.giveKeyboard(to: view)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text, view.markedTextRange == nil {
            view.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorField

        init(_ parent: EditorField) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text ?? ""
        }
    }
}

/// Whether the owner is writing, and a way to bring the keyboard back. Shared by the two layouts,
/// so that switching layout or coming back from the cover carries on where the owner was.
final class WritingFocus: ObservableObject {
    /// Counts the times the keyboard has been asked for; a change redraws the field.
    @Published private(set) var request = 0
    /// True from the moment the keyboard is asked for until a field takes it.
    var wantsKeyboard = false
    /// Set when the layout is about to change while the owner is writing: the next note field
    /// to be made takes the keyboard, so the writing carries on in the other layout.
    var handOver = false
    /// Whether the note field has the keyboard. Read when hiding or switching layout; nothing is
    /// drawn from it, so it is not published.
    var isWriting = false

    func ask() {
        wantsKeyboard = true
        request += 1
    }
}

/// The note field with its "Write a note" prompt.
struct NoteEntry: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var focus: WritingFocus
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if session.draft.isEmpty {
                Text("Write a note")
                    .font(Theme.note(size))
                    .foregroundStyle(Theme.secondary.opacity(0.6))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            NoteField(text: session.draft, font: Theme.noteUIFont(size), color: Theme.inkUI,
                      focus: focus, focusRequest: focus.request,
                      onChange: { session.noteChanged($0) },
                      onReturn: { session.noteFinished() })
        }
    }
}
