import ScrivnerCore
import SwiftUI

/// What a layout can ask the session screen to do.
struct SessionActions {
    let stop: () -> Void
    let close: () -> Void
    let hide: () -> Void
    let switchLayout: () -> Void
    let toggleLocation: () -> Void
    let details: () -> Void
    let edit: (PageRow) -> Void
}

/// A note being changed.
struct NoteEdit: Identifiable {
    let id: String
    var text: String
}

/// One session on screen: the page in whichever of the two layouts is chosen, with the cover over
/// it when hidden.
struct SessionView: View {
    @ObservedObject var session: SessionModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    /// "margin" (layout A) or "plain" (layout B). Remembered between sessions.
    @AppStorage("layout") private var layout = "margin"
    @StateObject private var focus = WritingFocus()
    @State private var covered = false
    @State private var wasWritingWhenCovered = false
    @State private var confirmingStop = false
    @State private var confirmingLocation = false
    @State private var showingDetails = false
    @State private var editing: NoteEdit?

    private let cover = BlankCover()

    var body: some View {
        ZStack {
            page
            if covered {
                cover.body(dismiss: { uncover() })
            } else if scenePhase != .active {
                // What the app switcher shows: never the page.
                PrivacyShade()
            }
        }
        .statusBarHidden(covered)
        .persistentSystemOverlays(covered ? .hidden : .automatic)
        .background(shortcuts)
        .onAppear {
            if session.isNew {
                session.isNew = false
                focus.ask()
            }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                session.saveNow()
            }
        }
        .confirmationDialog("Stop this session?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop session") {
                session.stop()
                // If it could not be finished, stay here, where the reason is shown.
                if session.isFinished {
                    model.closeSession()
                }
            }
            .accessibilityIdentifier("confirm-stop")
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Recording ends and the session is finished. You can open it again later to read it, add to it or record more.")
        }
        .alert(session.isLocationOn ? "Turn location off?" : "Turn location on?", isPresented: $confirmingLocation) {
            Button(session.isLocationOn ? "Turn off" : "Turn on") { session.setLocation(on: !session.isLocationOn) }
                .accessibilityIdentifier("confirm-location")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(session.isLocationOn
                ? "Nothing from now on will carry a place. Places already saved in this session stay where they are."
                : "From now on, each photo will carry the place it was taken. This cannot be taken out of a photo afterwards.")
        }
        .sheet(isPresented: $showingDetails) {
            SessionDetails(session: session)
        }
        .sheet(item: $editing) { note in
            NoteEditor(note: note) { text in
                session.revise(noteId: note.id, text: text)
            }
        }
    }

    @ViewBuilder
    private var page: some View {
        Group {
            if layout == "plain" {
                PlainLayout(session: session, focus: focus, actions: actions)
            } else {
                MarginLayout(session: session, focus: focus, actions: actions)
            }
        }
        .background(Theme.paper)
        // Sizes are worked out when a screen is drawn, so a new text size draws it afresh.
        .id(typeSize)
        // While covered the page takes no touches and is not read out.
        .allowsHitTesting(!covered)
        .accessibilityHidden(covered)
    }

    private var actions: SessionActions {
        SessionActions(
            stop: { confirmingStop = true },
            close: { model.closeSession() },
            hide: { hide() },
            switchLayout: {
                let wasWriting = focus.isWriting
                layout = (layout == "plain") ? "margin" : "plain"
                if wasWriting {
                    // The other layout has its own field; carry the keyboard over to it.
                    Task { @MainActor in focus.ask() }
                }
            },
            toggleLocation: { confirmingLocation = true },
            details: { showingDetails = true },
            edit: { row in
                if case .text(let text, _) = row.content {
                    editing = NoteEdit(id: row.id, text: text)
                }
            })
    }

    private func hide() {
        wasWritingWhenCovered = focus.isWriting
        dismissKeyboard()
        covered = true
    }

    private func uncover() {
        covered = false
        if wasWritingWhenCovered {
            focus.ask()
        }
    }

    /// Command-Shift-B ("blank") on an attached keyboard hides the page, and brings it back.
    private var shortcuts: some View {
        Button("Hide or show the page") {
            if covered {
                uncover()
            } else {
                hide()
            }
        }
        .keyboardShortcut("b", modifiers: [.command, .shift])
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// The switch between the two layouts, shown in both headers.
struct LayoutSwitch: View {
    let isMargin: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isMargin ? "sidebar.left" : "doc.plaintext")
                .font(Theme.ui(18))
                .frame(width: 44, height: 44)
                .foregroundStyle(isMargin ? Theme.accent : Theme.ink)
                .background(isMargin ? Theme.accentWash : Theme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isMargin ? Theme.accent : Theme.rule))
        }
        .accessibilityIdentifier("layout-switch")
        .accessibilityLabel(isMargin ? "Layout: times in the margin. Switch to plain page" : "Layout: plain page. Switch to times in the margin")
    }
}

/// The less-used things in the plain layout: the title and participants, location, and stopping.
struct SessionMenu: View {
    @ObservedObject var session: SessionModel
    let actions: SessionActions

    var body: some View {
        Menu {
            Button("Title and participants", systemImage: "pencil", action: actions.details)
            Button(session.isLocationOn ? "Turn location off" : "Turn location on",
                   systemImage: session.isLocationOn ? "location.slash" : "location", action: actions.toggleLocation)
            if session.isRecording || !session.isFinished {
                Button("Stop session", systemImage: "stop.circle", role: .destructive, action: actions.stop)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(Theme.ui(18, .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.rule))
        }
        .accessibilityIdentifier("session-menu")
        .accessibilityLabel("Session options")
    }
}

/// The session's title and its participant codes.
struct SessionDetails: View {
    @ObservedObject var session: SessionModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var participants = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("title-field")
                } footer: {
                    Text("Leave it empty and the session is known by its date and time.")
                }
                Section {
                    TextField("Participant codes", text: $participants)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("participants-field")
                } footer: {
                    Text("Codes, not names, separated by commas: for example P-014, P-015.")
                }
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.setTitle(title)
                        session.setParticipants(participants)
                        dismiss()
                    }
                    .accessibilityIdentifier("details-save")
                }
            }
            .onAppear {
                title = session.titleAsTyped
                participants = session.participants
            }
        }
    }
}

/// Changing a note that is already on the page. It keeps its time; the page marks it as edited.
struct NoteEditor: View {
    let note: NoteEdit
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var confirmingDelete = false

    init(note: NoteEdit, onSave: @escaping (String) -> Void) {
        self.note = note
        self.onSave = onSave
        _text = State(initialValue: note.text)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                EditorField(text: $text, font: Theme.noteUIFont(18), color: Theme.inkUI)
                    .padding(8)
                    .background(Theme.strip)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("The note keeps the time it was first written. The page will show that it was edited.")
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.secondary)
                Button("Delete this note", role: .destructive) { confirmingDelete = true }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("delete-note")
            }
            .padding(16)
            .background(Theme.paper)
            .navigationTitle("Edit note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .accessibilityIdentifier("save-note")
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete note", role: .destructive) {
                    onSave("")
                    dismiss()
                }
                .accessibilityIdentifier("confirm-delete-note")
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("It is removed from the page and from the session's record. This cannot be undone.")
            }
        }
    }
}

/// A line that stays for as long as something is wrong: recording interrupted, or changes not saved.
struct StateBanner: View {
    @ObservedObject var session: SessionModel

    var body: some View {
        VStack(spacing: 0) {
            if case .interrupted(let reason) = session.recorder {
                line("Not recording: \(reason). Recording will start again as soon as it can.", identifier: "interrupted")
            }
            if session.hasUnsavedChanges {
                line("The latest changes are not saved yet. Saving is being tried again.", identifier: "unsaved")
            }
        }
    }

    private func line(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(Theme.ui(13, .semibold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.alarm)
            .accessibilityIdentifier(identifier)
    }
}

/// Things the owner should know: a save that failed, a session that was repaired. Every one is
/// shown, oldest first, until the owner says OK.
struct NoticeBanner: View {
    let notices: [SessionNotice]
    let onDismiss: () -> Void

    var body: some View {
        if !notices.isEmpty {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(notices.enumerated()), id: \.offset) { _, notice in
                        Text(notice.text)
                            .font(Theme.ui(13))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("notice")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("OK", action: onDismiss)
                    .font(Theme.ui(13, .semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("dismiss-notice")
                    .accessibilityLabel("OK, dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Theme.accentWash)
        }
    }
}
