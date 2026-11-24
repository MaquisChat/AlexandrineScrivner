import ScrivnerCore
import SwiftUI

/// Layout B, "Plain page": reads like ordinary notes. The recorder is a small pill, there is no
/// margin, photos sit as thumbnails beside the text with their time underneath, and three round
/// buttons float at the bottom.
struct PlainLayout: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var focus: WritingFocus
    let actions: SessionActions

    var body: some View {
        VStack(spacing: 0) {
            TrialBanner()
            header
            NoticeBanner(notices: session.notices) { session.clearNotices() }
            StateBanner(session: session)
            page
        }
    }

    // MARK: - The header

    /// The controls sit on a line of their own, above the title, so that neither a long title nor
    /// large text can push one of them off the screen.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                LayoutSwitch(isMargin: false, action: actions.switchLayout)
                SessionMenu(session: session, actions: actions)
                if session.isFinished && !session.isRecording {
                    Button("Close", action: actions.close)
                        .font(Theme.ui(15, .semibold))
                        .fixedSize()
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("close")
                }
                Spacer(minLength: 0)
                pill
            }
            Button(action: actions.details) {
                Text(session.page.title)
                    .font(Theme.title(26))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("session-title")
            .accessibilityHint("Changes the title and participants")
            Text(session.participants.isEmpty ? session.startedLine : "\(session.participants) · \(session.startedLine)")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LocationButton(session: session, action: actions.toggleLocation)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// The recorder, small: a red dot and the counter while recording; the word for what it is
    /// doing instead of the dot when it is not.
    private var pill: some View {
        Button {
            session.isRecording ? session.pause() : session.resume()
        } label: {
            HStack(spacing: 8) {
                if session.isRecording {
                    Circle()
                        .fill(Theme.recording)
                        .frame(width: 9, height: 9)
                } else {
                    Image(systemName: stateSymbol)
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.ink)
                    Text(session.stateWord)
                        .font(Theme.ui(15, .semibold))
                        .foregroundStyle(Theme.ink)
                }
                Text(session.counter)
                    .font(Theme.ui(15, .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Theme.pill)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(session.isRecording ? Theme.rule : Theme.ink, lineWidth: session.isRecording ? 1 : 1.5))
        }
        .accessibilityIdentifier("pause-resume")
        .accessibilityLabel(session.isRecording ? "Pause recording" : "Resume recording")
        .accessibilityValue("\(session.stateWord), \(session.counter)")
    }

    private var stateSymbol: String {
        switch session.recorder {
        case .recording: return "record.circle"
        case .paused: return "pause.fill"
        case .interrupted: return "exclamationmark.triangle.fill"
        case .stopped: return "stop.fill"
        }
    }

    // MARK: - The page

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(PlainBlock.blocks(from: session.rows)) { block in
                        PlainBlockView(block: block, session: session, onEdit: actions.edit)
                    }
                    NoteEntry(session: session, focus: focus, size: 19)
                        .id("note-field")
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            // The buttons take their own room at the bottom, above the keyboard when it is up,
            // so the line being written is never underneath them.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                floatingButtons
                    .padding(.top, 6)
                    .padding(.bottom, 10)
            }
            .onChange(of: session.rows.count) {
                withAnimation { proxy.scrollTo("note-field", anchor: .bottom) }
            }
            .onAppear {
                proxy.scrollTo("note-field", anchor: .bottom)
            }
        }
    }

    private var floatingButtons: some View {
        HStack(spacing: 8) {
            RoundButton(systemImage: "camera", label: "Take photo", identifier: "photo") { session.takePhoto() }
            RoundButton(systemImage: "video", label: "Video", identifier: "video") {}
                .disabled(true)
                .opacity(0.4)
                .accessibilityHint("Video clips come in a later version")
            RoundButton(systemImage: "eye.slash", label: "Hide", identifier: "hide", filled: true, action: actions.hide)
        }
        .padding(8)
        .background(Theme.paper)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.rule))
        .shadow(color: Color.black.opacity(0.14), radius: 10, y: 6)
    }
}

/// A round button in the floating set.
private struct RoundButton: View {
    let systemImage: String
    let label: String
    let identifier: String
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(Theme.ui(21))
                .frame(width: 56, height: 56)
                .foregroundStyle(filled ? Theme.onInk : Theme.ink)
                .background(filled ? Theme.ink : Theme.paper)
                .clipShape(Circle())
                .overlay(Circle().stroke(filled ? Theme.ink : Theme.outline))
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(label)
    }
}

/// The plain page groups each note with the photos and clips made straight after it, so they can
/// sit beside it. Markers stand alone.
struct PlainBlock: Identifiable {
    enum Kind {
        case marker(String)
        /// A note (nil when photos stand on their own) and what was made straight after it.
        case note(row: PageRow?, media: [PageRow])
    }

    let id: String
    let kind: Kind

    static func blocks(from rows: [PageRow]) -> [PlainBlock] {
        var blocks: [PlainBlock] = []
        var index = 0
        while index < rows.count {
            let row = rows[index]
            switch row.content {
            case .marker(let text):
                blocks.append(PlainBlock(id: row.id, kind: .marker(text)))
                index += 1
            case .text:
                var media: [PageRow] = []
                var next = index + 1
                while next < rows.count, rows[next].isMedia {
                    media.append(rows[next])
                    next += 1
                }
                blocks.append(PlainBlock(id: row.id, kind: .note(row: row, media: media)))
                index = next
            case .photo, .video, .ink:
                var media: [PageRow] = []
                var next = index
                while next < rows.count, rows[next].isMedia {
                    media.append(rows[next])
                    next += 1
                }
                blocks.append(PlainBlock(id: row.id, kind: .note(row: nil, media: media)))
                index = next
            }
        }
        return blocks
    }
}

private extension PageRow {
    var isMedia: Bool {
        switch content {
        case .photo, .video, .ink: return true
        case .marker, .text: return false
        }
    }
}

private struct PlainBlockView: View {
    let block: PlainBlock
    @ObservedObject var session: SessionModel
    let onEdit: (PageRow) -> Void

    var body: some View {
        switch block.kind {
        case .marker(let text):
            HStack(spacing: 10) {
                Rectangle().fill(Theme.rule).frame(height: 1)
                Text(text)
                    .font(Theme.ui(12))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .accessibilityIdentifier("marker")
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
        case .note(let row, let media):
            HStack(alignment: .top, spacing: 14) {
                if let row, case .text(let text, let edited) = row.content {
                    NoteText(text: text, edited: edited, size: 19) { onEdit(row) }
                } else {
                    Spacer(minLength: 0)
                }
                if !media.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(media) { row in
                            PlainMedia(row: row, session: session)
                        }
                    }
                }
            }
        }
    }
}

/// A thumbnail with its time underneath.
private struct PlainMedia: View {
    let row: PageRow
    @ObservedObject var session: SessionModel

    var body: some View {
        VStack(spacing: 4) {
            switch row.content {
            case .photo(let file):
                PhotoThumbnail(url: session.url(for: file), side: 76, square: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel("Photo taken at \(row.time)")
                    .accessibilityIdentifier("photo-row")
            case .video:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.ink)
                    .frame(width: 76, height: 76)
                    .overlay(Image(systemName: "play.fill").foregroundStyle(Theme.onInk))
                    .accessibilityLabel("Video clip made at \(row.time)")
            default:
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.thumbnail)
                    .frame(width: 76, height: 76)
                    .overlay(Image(systemName: "pencil.tip").foregroundStyle(Theme.secondary))
            }
            Text(row.time)
                .font(Theme.ui(12))
                .monospacedDigit()
                .foregroundStyle(Theme.secondary)
        }
    }
}
