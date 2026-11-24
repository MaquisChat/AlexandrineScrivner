import ScrivnerCore
import SwiftUI

/// Layout A, "Times in the margin": a full recorder bar at the top, the clock time of every row
/// down the left margin, and a bottom bar with labelled buttons.
struct MarginLayout: View {
    @ObservedObject var session: SessionModel
    let actions: SessionActions
    @FocusState private var writing: Bool

    var body: some View {
        VStack(spacing: 0) {
            recorderBar
            strip
            NoticeBanner(notices: session.notices) { session.clearNotices() }
            StateBanner(session: session)
            page
            bottomBar
        }
    }

    // MARK: - The recorder bar

    private var recorderBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.isRecording ? Theme.recording : Theme.outline)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(stateWord)
                    .font(.system(size: 12, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(session.isRecording ? Theme.recording : Theme.secondary)
                    // Said as an ordinary word, not spelled out in capitals.
                    .accessibilityLabel(stateWord)
                    .accessibilityIdentifier("recorder-state")
                Text(session.counter)
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("counter")
                    .accessibilityLabel("Recorded \(session.counter)")
            }
            Spacer(minLength: 0)
            LayoutSwitch(isMargin: true, action: actions.switchLayout)
            Button {
                session.isRecording ? session.pause() : session.resume()
            } label: {
                Image(systemName: session.isRecording ? "pause.fill" : "record.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(session.isRecording ? Theme.ink : Theme.recording)
                    .overlay(Circle().stroke(Theme.outline))
            }
            .accessibilityIdentifier("pause-resume")
            .accessibilityLabel(session.isRecording ? "Pause recording" : "Resume recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    /// One word for what the recorder is doing.
    private var stateWord: String {
        switch session.recorder {
        case .recording: return "Recording"
        case .paused: return "Paused"
        case .interrupted: return "Interrupted"
        case .stopped: return "Stopped"
        }
    }

    // MARK: - The strip under it

    private var strip: some View {
        HStack(spacing: 8) {
            Button(action: actions.rename) {
                Text(session.participants.isEmpty ? session.page.title : "\(session.page.title) · \(session.participants)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .frame(minHeight: 32)
            }
            .accessibilityIdentifier("session-title")
            .accessibilityHint("Renames the session")
            Spacer(minLength: 8)
            Button(action: actions.toggleLocation) {
                Label(session.isLocationOn ? "Location on" : "Location off",
                      systemImage: session.isLocationOn ? "location.fill" : "location.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .labelStyle(.titleAndIcon)
                    .frame(minHeight: 32)
            }
            .accessibilityIdentifier("location-state")
            .accessibilityLabel(session.isLocationOn ? "Location on" : "Location off")
            .accessibilityHint(session.isLocationOn ? "Turns location off" : "Turns location on")
            if session.isRecording || !session.isFinished {
                Button("Stop", action: actions.stop)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.recording)
                    .frame(minWidth: 44, minHeight: 32)
                    .accessibilityIdentifier("stop")
                    .accessibilityLabel("Stop session")
            } else {
                Button("Close", action: actions.close)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 32)
                    .accessibilityIdentifier("close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.strip)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    // MARK: - The page

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(session.rows) { row in
                        MarginRow(row: row, session: session)
                    }
                    noteField
                        .id("note-field")
                }
                .padding(.top, 18)
                .padding(.bottom, 24)
                .padding(.trailing, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.rows.count) {
                withAnimation { proxy.scrollTo("note-field", anchor: .bottom) }
            }
        }
    }

    private var noteField: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(session.draftTime)
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .frame(width: MarginRow.marginWidth(for: session.style), alignment: .trailing)
                .padding(.top, 5)
                .accessibilityHidden(true)
            TextField("Write a note", text: Binding(get: { session.draft }, set: { session.noteChanged($0) }), axis: .vertical)
                .font(Theme.note(18))
                .foregroundStyle(Theme.ink)
                .lineSpacing(4)
                .focused($writing)
                .submitLabel(.return)
                .onSubmit {
                    session.noteFinished()
                    writing = true
                }
                .accessibilityIdentifier("note-field")
        }
    }

    // MARK: - The bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            BarButton(title: "Photo", systemImage: "camera", identifier: "photo") { session.takePhoto() }
            BarButton(title: "Video", systemImage: "video", identifier: "video") {}
                .disabled(true)
                .opacity(0.4)
                .accessibilityHint("Video clips come in a later version")
            Spacer(minLength: 0)
            Button {
                writing = false
                actions.hide()
            } label: {
                Label("Hide", systemImage: "eye.slash")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(minWidth: 120, minHeight: 52)
                    .foregroundStyle(Color.white)
                    .background(Theme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityIdentifier("hide")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.paper)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }
}

/// A labelled button in the bottom bar.
private struct BarButton: View {
    let title: String
    let systemImage: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(minWidth: 64, minHeight: 52)
            .foregroundStyle(Theme.ink)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline))
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title == "Photo" ? "Take photo" : title)
    }
}
