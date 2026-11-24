import ScrivnerCore
import SwiftUI

/// The home screen: every session, newest first, and the way to start one.
struct SessionListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingSettings = false
    @State private var deleting: SessionSummary?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !model.installWarning.text.isEmpty {
                    InstallBanner(warning: model.installWarning)
                }
                if model.sessions.isEmpty && model.unreadable.isEmpty {
                    emptyState
                } else {
                    list
                }
                newSessionButton
            }
            .background(Theme.paper)
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("settings")
                    .accessibilityLabel("Settings")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $model.sharing) { zip in
            ShareSheet(url: zip.url) { completed in
                model.finishedSharing(zip, completed: completed)
            }
        }
        .confirmationDialog(deleting.map { "Delete “\($0.title)”?" } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                if let deleting { model.delete(deleting) }
                deleting = nil
            }
            .accessibilityIdentifier("confirm-delete")
            Button("Keep it", role: .cancel) { deleting = nil }
        } message: {
            Text("Its recording, photos and notes will be removed from this iPhone. This cannot be undone.")
        }
        .alert("Before you start", isPresented: Binding(get: { model.readiness != nil }, set: { if !$0 { model.readiness = nil } })) {
            Button("Start anyway") {
                model.readiness = nil
                model.startSession()
            }
            Button("Cancel", role: .cancel) { model.readiness = nil }
        } message: {
            Text(model.readiness ?? "")
        }
        .fullScreenCover(item: $model.openSession, onDismiss: { model.refresh() }) { session in
            SessionView(session: session)
                .environmentObject(model)
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.problem != nil }, set: { if !$0 { model.problem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.problem ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("No sessions yet")
                .font(Theme.note(24))
                .foregroundStyle(Theme.ink)
            Text("A session records audio while you write notes and take photos. Everything is stamped with its time.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List {
            ForEach(model.sessions, id: \.listId) { summary in
                Button {
                    model.open(summary)
                } label: {
                    SessionRow(summary: summary, style: model.clockStyle)
                }
                .accessibilityIdentifier("session-row")
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        deleting = summary
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityIdentifier("delete")
                    if summary.isFinished {
                        Button {
                            model.share(summary)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .tint(Theme.accent)
                        .accessibilityIdentifier("share")
                    }
                }
            }
            ForEach(model.unreadable, id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("This session's record cannot be read. Its recordings are still in the Files app.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.recording)
                }
            }
        }
        .listStyle(.plain)
    }

    private var newSessionButton: some View {
        Button {
            model.newSession()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.recording)
                    .frame(width: 12, height: 12)
                Text("New session")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Theme.ink)
            .background(Theme.pill)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.rule))
        }
        .accessibilityIdentifier("new-session")
        .accessibilityHint("Starts recording at once")
        .padding(16)
    }
}

/// One session in the list.
private struct SessionRow: View {
    let summary: SessionSummary
    let style: ClockStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(summary.title)
                .font(Theme.note(20))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(summary.isFinished ? Theme.accent : Theme.recording)
                    .accessibilityIdentifier("session-status")
            }
        }
        .padding(.vertical, 6)
    }

    private var detail: String {
        let clock = LocalClock(summary.startedAt, offset: summary.utcOffset)
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
        var parts = ["\(clock.year)-\(two(clock.month))-\(two(clock.day)) "
            + Wording.clock(summary.startedAt, offset: summary.utcOffset, style: style)]
        parts.append(Wording.length(milliseconds: summary.recordedMilliseconds) + " recorded")
        if summary.photoCount > 0 {
            parts.append(summary.photoCount == 1 ? "1 photo" : "\(summary.photoCount) photos")
        }
        if summary.clipCount > 0 {
            parts.append(summary.clipCount == 1 ? "1 clip" : "\(summary.clipCount) clips")
        }
        return parts.joined(separator: " · ")
    }

    private var status: String {
        guard summary.isFinished else { return "Not finished" }
        switch summary.export {
        case .never: return "Not shared yet"
        case .exported(let when):
            let clock = LocalClock(when, offset: summary.utcOffset)
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            return "Shared \(clock.day) \(months[max(0, min(11, clock.month - 1))]), \(Wording.clock(when, offset: summary.utcOffset, style: style))"
        case .changedSince: return "Changed since it was shared"
        }
    }
}

/// How long the install has left, when the app can tell.
private struct InstallBanner: View {
    let warning: InstallWarning

    var body: some View {
        Text(warning.text)
            .font(.system(size: 13, weight: warning.isUrgent ? .semibold : .regular))
            .foregroundStyle(warning.isUrgent ? Color.white : Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(warning.isUrgent ? Theme.recording : Theme.strip)
            .accessibilityIdentifier("install-warning")
    }
}
