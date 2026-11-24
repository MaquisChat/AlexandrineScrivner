import ScrivnerCore
import SwiftUI

/// Layout B, "Plain page": reads like ordinary notes. The recorder is a small pill, there is no
/// margin, photos sit as thumbnails beside the text with their time underneath, and three round
/// buttons float at the bottom.
struct PlainLayout: View {
    @ObservedObject var session: SessionModel
    let actions: SessionActions
    @FocusState private var writing: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                NoticeBanner(notices: session.notices) { session.clearNotices() }
                StateBanner(session: session)
                page
            }
            floatingButtons
                .padding(.bottom, 14)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.page.title)
                    .font(Theme.note(26))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .accessibilityIdentifier("session-title")
                Text(session.startedLine)
                    .font(Theme.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            SessionMenu(session: session, actions: actions)
            LayoutSwitch(isMargin: false, action: actions.switchLayout)
            Button {
                session.isRecording ? session.pause() : session.resume()
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.isRecording ? Theme.recording : Theme.outline)
                        .frame(width: 9, height: 9)
                    Text(session.counter)
                        .font(Theme.ui(15, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Theme.pill)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.rule))
            }
            .accessibilityIdentifier("pause-resume")
            .accessibilityLabel(session.isRecording ? "Recording, \(session.counter). Pause" : "Paused at \(session.counter). Resume")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(PlainBlock.blocks(from: session.rows)) { block in
                        PlainBlockView(block: block, session: session)
                    }
                    TextField("Write a note", text: Binding(get: { session.draft }, set: { session.noteChanged($0) }), axis: .vertical)
                        .font(Theme.note(19))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(5)
                        .focused($writing)
                        .submitLabel(.return)
                        .onSubmit {
                            session.noteFinished()
                            writing = true
                        }
                        .accessibilityIdentifier("note-field")
                        .id("note-field")
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.rows.count) {
                withAnimation { proxy.scrollTo("note-field", anchor: .bottom) }
            }
        }
    }

    private var floatingButtons: some View {
        HStack(spacing: 8) {
            RoundButton(systemImage: "camera", label: "Take photo", identifier: "photo") { session.takePhoto() }
            RoundButton(systemImage: "video", label: "Video", identifier: "video") {}
                .disabled(true)
                .opacity(0.4)
            RoundButton(systemImage: "eye.slash", label: "Hide", identifier: "hide", filled: true) {
                writing = false
                actions.hide()
            }
        }
        .padding(8)
        .background(Theme.paper)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.rule))
        .shadow(color: Theme.ink.opacity(0.14), radius: 10, y: 6)
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
                .foregroundStyle(filled ? Color.white : Theme.ink)
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
        case note(text: String?, edited: Bool, media: [PageRow])
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
            case .text(let text, let edited):
                var media: [PageRow] = []
                var next = index + 1
                while next < rows.count, rows[next].isMedia {
                    media.append(rows[next])
                    next += 1
                }
                blocks.append(PlainBlock(id: row.id, kind: .note(text: text, edited: edited, media: media)))
                index = next
            case .photo, .video, .ink:
                var media: [PageRow] = []
                var next = index
                while next < rows.count, rows[next].isMedia {
                    media.append(rows[next])
                    next += 1
                }
                blocks.append(PlainBlock(id: row.id, kind: .note(text: nil, edited: false, media: media)))
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
                    .accessibilityIdentifier("marker")
                Rectangle().fill(Theme.rule).frame(height: 1)
            }
        case .note(let text, let edited, let media):
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    if let text {
                        Text(text)
                            .font(Theme.note(19))
                            .lineSpacing(5)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("note")
                    }
                    if edited {
                        Text("edited")
                            .font(Theme.ui(11))
                            .foregroundStyle(Theme.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .overlay(Image(systemName: "play.fill").foregroundStyle(Color.white))
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
