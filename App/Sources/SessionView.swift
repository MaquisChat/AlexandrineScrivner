import ScrivnerCore
import SwiftUI

/// One session on screen. Stage 1b shows it in the margin layout; the plain layout and the
/// switch between them come next.
struct SessionView: View {
    @ObservedObject var session: SessionModel
    @EnvironmentObject private var model: AppModel
    @State private var confirmingStop = false

    var body: some View {
        MarginLayout(session: session, onStop: { confirmingStop = true }, onClose: { model.closeSession() })
            .background(Theme.paper)
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
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("notice")
                Button("OK", action: onDismiss)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityIdentifier("dismiss-notice")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.accentWash)
        }
    }
}
