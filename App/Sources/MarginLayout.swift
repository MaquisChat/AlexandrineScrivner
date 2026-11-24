import ScrivnerCore
import SwiftUI

/// Layout A, "Times in the margin": a full recorder bar at the top, the clock time of every row
/// down the left margin, and a bottom bar with labelled buttons.
struct MarginLayout: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var focus: WritingFocus
    let actions: SessionActions

    var body: some View {
        VStack(spacing: 0) {
            TrialBanner()
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
                Text(session.stateWord)
                    .font(Theme.ui(12, .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(session.isRecording ? Theme.recording : Theme.secondary)
                    // Said as an ordinary word, not spelled out in capitals.
                    .accessibilityLabel(session.stateWord)
                    .accessibilityIdentifier("recorder-state")
                Text(session.counter)
                    .font(Theme.ui(26, .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
                    .font(Theme.ui(20, .semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(session.isRecording ? Theme.ink : Theme.recording)
                    .overlay(Circle().stroke(Theme.outline))
            }
            .accessibilityIdentifier("pause-resume")
            .accessibilityLabel(session.isRecording ? "Pause recording" : "Resume recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    // MARK: - The strip under it

    private var strip: some View {
        HStack(spacing: 8) {
            Button(action: actions.details) {
                Text(session.participants.isEmpty ? session.page.title : "\(session.page.title) · \(session.participants)")
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("session-title")
            .accessibilityHint("Changes the title and participants")
            Spacer(minLength: 8)
            LocationButton(session: session, action: actions.toggleLocation)
            if session.isRecording || !session.isFinished {
                Button("Stop", action: actions.stop)
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.recording)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("stop")
                    .accessibilityLabel("Stop session")
            } else {
                Button("Close", action: actions.close)
                    .font(Theme.ui(13, .semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("close")
            }
        }
        .padding(.horizontal, 16)
        .background(Theme.strip)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    // MARK: - The page

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(session.rows) { row in
                        MarginRow(row: row, session: session, onEdit: actions.edit)
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
            .onAppear {
                // A session opened to be read starts where it left off, not at its first line.
                proxy.scrollTo("note-field", anchor: .bottom)
            }
        }
    }

    private var noteField: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(session.draftTime)
                .font(Theme.ui(12))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
                .frame(width: MarginRow.marginWidth(for: session.style), alignment: .trailing)
                .padding(.top, 5)
                .accessibilityHidden(true)
            NoteEntry(session: session, focus: focus, size: 18)
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
            Button(action: actions.hide) {
                Label("Hide", systemImage: "eye.slash")
                    .font(Theme.ui(17, .semibold))
                    .frame(minWidth: 120, minHeight: 52)
                    .foregroundStyle(Theme.onInk)
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

/// Whether location is on, in the header of both layouts. Tapping it asks before changing anything.
struct LocationButton: View {
    @ObservedObject var session: SessionModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(session.isLocationOn ? "Location on" : "Location off",
                  systemImage: session.isLocationOn ? "location.fill" : "location.slash")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .frame(minHeight: 44)
        }
        .accessibilityIdentifier("location-state")
        .accessibilityLabel(session.isLocationOn ? "Location on" : "Location off")
        .accessibilityHint(session.isLocationOn ? "Turns location off" : "Turns location on")
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
                    .font(Theme.ui(20))
                Text(title)
                    .font(Theme.ui(12, .medium))
            }
            .frame(minWidth: 64, minHeight: 52)
            .foregroundStyle(Theme.ink)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline))
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title == "Photo" ? "Take photo" : title)
    }
}
