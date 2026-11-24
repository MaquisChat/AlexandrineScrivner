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
            UserDefaults.standard.removeObject(forKey: "layout")
            UserDefaults.standard.removeObject(forKey: "locationOnForNewSessions")
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
            problem = "The session could not be made ready to share. \(error.localizedDescription)"
        }
    }

    /// The share sheet has closed. If the owner went through with it, the session is marked as shared.
    func finishedSharing(_ zip: SharedZip, completed: Bool) {
        try? FileManager.default.removeItem(at: zip.url)
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
            problem = "The session could not be deleted. \(error.localizedDescription)"
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
