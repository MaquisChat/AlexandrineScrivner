import Foundation
import ScrivnerCore
import SwiftUI
import UIKit

/// The app's own state: where sessions are kept, the list of them, and which one is open.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var unreadable: [String] = []
    @Published private(set) var installWarning: InstallWarning = .unknown
    @Published var openSession: SessionModel?
    @Published var problem: String?
    /// What to say before a session starts when storage or battery is low; nil when there is nothing to say.
    @Published var readiness: String?
    /// A zip that is ready for the share sheet.
    @Published var sharing: SharedZip?
    /// What was found and put right when the app opened: sessions cut off when it was last closed.
    @Published var launchNotes: [String] = []

    /// Dark, when the automatic walkthrough asks for it (simulator only); otherwise nil, and the
    /// app follows the phone.
    let appearanceForWalkthrough: ColorScheme?

    /// Where every session's folder lives: Documents/Sessions, visible in the Files app.
    let sessionsRoot: URL
    /// When each session was last shared. Kept beside the sessions folder, never inside a session.
    let exportsFile: URL

    init() {
        // The arguments the automatic walkthrough passes only mean anything in the simulator.
        // On a real phone nothing can make the app clear its sessions.
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        #else
        let arguments: [String] = []
        #endif
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        sessionsRoot = documents.appendingPathComponent("Sessions", isDirectory: true)
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        exportsFile = support.appendingPathComponent("exports.json")
        if arguments.contains("-resetSessions") {
            try? fileManager.removeItem(at: sessionsRoot)
            try? fileManager.removeItem(at: exportsFile)
            UserDefaults.standard.removeObject(forKey: "layout")
            UserDefaults.standard.removeObject(forKey: "locationOnForNewSessions")
        }
        standInLocationIsOn = arguments.contains("-uiTestingLocation")
        appearanceForWalkthrough = arguments.contains("-uiTestingDark") ? .dark : nil
        try? fileManager.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        // Sessions stay on this phone: they are kept out of iCloud and computer backups. Set on the
        // folder, and again at every launch, because each save replaces the files inside it.
        var keptOut = URLResourceValues()
        keptOut.isExcludedFromBackup = true
        var root = sessionsRoot
        try? root.setResourceValues(keptOut)
        // A zip left from a share that was never finished (the app was closed with the sheet up).
        ShareSession.clearWaitingRoom()
        refreshInstallWarning()
        repairSessionsThatWereCutOff()
        refresh()
    }

    /// How long this install has left, read from the app's own install profile.
    func refreshInstallWarning() {
        if let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: profile) {
            installWarning = InstallWarning.state(expires: InstallWarning.expiry(inProfile: data), now: Instant(date: Date()))
        }
    }

    /// A session that was recording when the app was last closed is put right as soon as the app
    /// opens: closed at the length of the audio that was kept, and made complete, so it can be
    /// copied out as it stands. The list says what was done.
    private func repairSessionsThatWereCutOff() {
        for folder in SessionStore.sessions(in: sessionsRoot) {
            guard let manifest = try? SessionStore.load(folder),
                  SessionTimeline(resuming: manifest, ids: RandomIdSource()).needsRecovery else { continue }
            // Location is left exactly as the session had it; the setting applies when it is next opened.
            guard let repaired = try? SessionController.open(
                folder, locationOn: true, clock: SystemClock(), audio: StandInAudio(),
                location: StandInLocation(isOn: false), ids: RandomIdSource(),
                audioLength: { StandInAudio.length(of: $0) }) else { continue }
            var note = "“\(repaired.manifest.displayTitle)” was still recording when the app was last closed. Everything saved up to then has been kept."
            for notice in repaired.notices {
                if case .recovered(let dropped) = notice, !dropped.isEmpty {
                    note += " Not kept, because \(dropped.count == 1 ? "it" : "they") had not been saved: \(dropped.joined(separator: ", "))."
                }
                if case .filesNotListed(let files) = notice {
                    note += " In its folder but not on its page: \(files.joined(separator: ", "))."
                }
            }
            launchNotes.append(note)
        }
    }

    var clockStyle: ClockStyle {
        // "j" asks for the hour in the device's own style; an "a" in the answer means am and pm.
        let format = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: Locale.current) ?? ""
        return format.contains("a") ? .twelveHour : .twentyFourHour
    }

    func refresh() {
        let list = SessionSummary.list(in: sessionsRoot, exports: ExportRecord.load(from: exportsFile))
        sessions = list.sessions
        unreadable = list.unreadable
    }

    /// Starts a new session, unless storage or battery is low, in which case the owner is asked first.
    func newSession() {
        let warnings = ReadinessWarning.check(freeBytes: freeBytes, batteryLevel: batteryLevel, isCharging: isCharging)
        if warnings.isEmpty {
            startSession()
        } else {
            readiness = warnings.map(\.text).joined(separator: "\n\n")
        }
    }

    /// Shares a finished session as one zip.
    func share(_ summary: SessionSummary) {
        do {
            sharing = SharedZip(url: try ShareSession.zip(of: summary.folder.url), sessionId: summary.id)
        } catch {
            problem = "The session could not be made ready to share. Check that the phone has free storage, then try again."
        }
    }

    /// The share sheet has closed. If the owner went through with it, the session is marked as shared.
    func finishedSharing(_ zip: SharedZip, completed: Bool) {
        ShareSession.clearWaitingRoom()
        if completed, let summary = sessions.first(where: { $0.id == zip.sessionId }),
           let data = try? Data(contentsOf: summary.folder.sessionJSON),
           let manifest = try? SessionStore.load(summary.folder) {
            var record = ExportRecord.load(from: exportsFile)
            record.noteExport(of: manifest, sessionJSON: data, at: Instant(date: Date()))
            try? record.save(to: exportsFile)
        }
        refresh()
    }

    /// Deletes a session and everything in it. The screen asks first.
    func delete(_ summary: SessionSummary) {
        do {
            try SessionStore.delete(summary.folder)
            var record = ExportRecord.load(from: exportsFile)
            record.forget(sessionId: summary.id)
            try? record.save(to: exportsFile)
        } catch {
            problem = "The session could not be deleted."
        }
        refresh()
    }

    private var freeBytes: Int64? {
        let values = try? sessionsRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    private var batteryLevel: Double? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return Double(UIDevice.current.batteryLevel)
    }

    private var isCharging: Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        return UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }

    /// Starts a new session, which begins recording at once, and opens it.
    func startSession() {
        guard openSession == nil else { return }
        do {
            openSession = try SessionModel.start(in: sessionsRoot, locationOn: locationOnForNewSessions,
                                                 standInLocation: standInLocationIsOn, style: clockStyle)
        } catch {
            problem = "The session could not be started. Check that the phone has free storage, then try again."
        }
        refresh()
    }

    /// Opens a session from the list. One that was cut off is repaired first.
    func open(_ summary: SessionSummary) {
        guard openSession == nil else { return }
        do {
            openSession = try SessionModel.open(summary.folder, locationOn: locationOnForNewSessions,
                                                standInLocation: standInLocationIsOn, style: clockStyle)
        } catch {
            problem = "The session could not be opened. Its recordings are still in its folder, which you can see in the Files app."
        }
        refresh()
    }

    func closeSession() {
        openSession?.leave()
        openSession = nil
        refresh()
    }

    private var locationOnForNewSessions: Bool {
        UserDefaults.standard.object(forKey: "locationOnForNewSessions") as? Bool ?? true
    }

    /// The stand-in location chip gives a place only when the walkthrough asks it to.
    private let standInLocationIsOn: Bool
}
