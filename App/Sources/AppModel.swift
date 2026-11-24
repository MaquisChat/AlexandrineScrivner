import Foundation
import ScrivnerCore
import SwiftUI

/// The app's own state: where sessions are kept, the list of them, and which one is open.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var unreadable: [String] = []
    @Published private(set) var installWarning: InstallWarning = .unknown
    @Published var openSession: SessionModel?
    @Published var problem: String?

    /// Where every session's folder lives: Documents/Sessions, visible in the Files app.
    let sessionsRoot: URL
    /// When each session was last shared. Kept beside the sessions folder, never inside a session.
    let exportsFile: URL
    /// True when a UI test is driving the app: stand-in location is switched on by its own argument.
    let isUITesting: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        isUITesting = arguments.contains("-uiTesting")
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        sessionsRoot = documents.appendingPathComponent("Sessions", isDirectory: true)
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        exportsFile = support.appendingPathComponent("exports.json")
        if arguments.contains("-resetSessions") {
            try? fileManager.removeItem(at: sessionsRoot)
            try? fileManager.removeItem(at: exportsFile)
        }
        try? fileManager.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        if let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: profile) {
            installWarning = InstallWarning.state(expires: InstallWarning.expiry(inProfile: data), now: Instant(date: Date()))
        }
        refresh()
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

    /// Starts a new session, which begins recording at once, and opens it.
    func startSession() {
        do {
            openSession = try SessionModel.start(in: sessionsRoot, locationOn: locationOnForNewSessions,
                                                 standInLocation: standInLocationIsOn, style: clockStyle)
        } catch {
            problem = "The session could not be started. \(error.localizedDescription)"
        }
        refresh()
    }

    /// Opens a session from the list. One that was cut off is repaired first.
    func open(_ summary: SessionSummary) {
        do {
            openSession = try SessionModel.open(summary.folder, locationOn: locationOnForNewSessions,
                                                standInLocation: standInLocationIsOn, style: clockStyle)
        } catch {
            problem = "The session could not be opened. \(error.localizedDescription)"
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

    private var standInLocationIsOn: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTestingLocation")
    }
}
