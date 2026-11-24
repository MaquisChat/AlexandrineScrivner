import ScrivnerCore
import SwiftUI

/// What a layout can ask the session screen to do.
struct SessionActions {
    let stop: () -> Void
    let close: () -> Void
    let hide: () -> Void
    let switchLayout: () -> Void
    let toggleLocation: () -> Void
    let rename: () -> Void
}

/// One session on screen: the page in whichever of the two layouts is chosen, with the cover over
/// it when hidden.
struct SessionView: View {
    @ObservedObject var session: SessionModel
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// "margin" (layout A) or "plain" (layout B). Remembered between sessions.
    @AppStorage("layout") private var layout = "margin"
    @State private var covered = false
    @State private var confirmingStop = false
    @State private var confirmingLocationOff = false
    @State private var renaming = false
    @State private var newTitle = ""

    private let cover = BlankCover()

    var body: some View {
        ZStack {
            page
            if covered {
                cover.body(dismiss: { covered = false })
            } else if scenePhase != .active {
                // What the app switcher shows: never the page.
                PrivacyShade()
            }
        }
        .statusBarHidden(covered)
        .persistentSystemOverlays(covered ? .hidden : .automatic)
        .background(shortcuts)
        .confirmationDialog("Stop this session?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop session") {
                session.stop()
                model.closeSession()
            }
            .accessibilityIdentifier("confirm-stop")
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Recording ends and the session is finished. You can open it again later to read it, add to it or record more.")
        }
        .alert("Turn location off?", isPresented: $confirmingLocationOff) {
            Button("Turn off") { session.setLocation(on: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Nothing from now on will carry a place. Places already saved in this session's photos stay in them.")
        }
        .alert("Session title", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Save") { session.setTitle(newTitle) }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var page: some View {
        Group {
            if layout == "plain" {
                PlainLayout(session: session, actions: actions)
            } else {
                MarginLayout(session: session, actions: actions)
            }
        }
        .background(Theme.paper)
        // While covered the page takes no touches and is not read out.
        .allowsHitTesting(!covered)
        .accessibilityHidden(covered)
    }

    private var actions: SessionActions {
        SessionActions(
            stop: { confirmingStop = true },
            close: { model.closeSession() },
            hide: { hide() },
            switchLayout: { layout = (layout == "plain") ? "margin" : "plain" },
            toggleLocation: {
                if session.isLocationOn {
                    confirmingLocationOff = true
                } else {
                    session.setLocation(on: true)
                }
            },
            rename: {
                newTitle = session.titleAsTyped
                renaming = true
            })
    }

    private func hide() {
        dismissKeyboard()
        covered = true
    }

    /// Command-Shift-H on an attached keyboard hides the page, and brings it back.
    private var shortcuts: some View {
        Button("Hide or show the page") {
            if covered {
                covered = false
            } else {
                hide()
            }
        }
        .keyboardShortcut("h", modifiers: [.command, .shift])
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

/// The less-used things: the title, location, and stopping.
struct SessionMenu: View {
    @ObservedObject var session: SessionModel
    let actions: SessionActions

    var body: some View {
        Menu {
            Button("Rename session", systemImage: "pencil", action: actions.rename)
            Button(session.isLocationOn ? "Turn location off" : "Turn location on",
                   systemImage: session.isLocationOn ? "location.slash" : "location", action: actions.toggleLocation)
            if session.isFinished && !session.isRecording {
                Button("Close", systemImage: "xmark", action: actions.close)
            } else {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.recording)
            .accessibilityIdentifier(identifier)
    }
}

/// A banner for something the owner should know: a save that failed, a session that was repaired.
struct NoticeBanner: View {
    let notices: [SessionNotice]
    let onDismiss: () -> Void

    var body: some View {
        if let latest = notices.last {
            HStack(alignment: .top, spacing: 10) {
                Text(latest.text)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("notice")
                Button("OK", action: onDismiss)
                    .font(Theme.ui(13, .semibold))
                    .accessibilityIdentifier("dismiss-notice")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.accentWash)
        }
    }
}
