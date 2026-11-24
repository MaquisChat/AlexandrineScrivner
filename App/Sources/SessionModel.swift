import Foundation
import ScrivnerCore
import SwiftUI

/// One open session, as the screens see it. Everything that decides anything is in
/// `SessionController`; this republishes what it says and passes on what the owner does.
@MainActor
final class SessionModel: ObservableObject, Identifiable {
    let id = UUID()
    let style: ClockStyle

    @Published private(set) var page: Page
    /// The page's rows, without the note that is being written.
    @Published private(set) var rows: [PageRow] = []
    @Published private(set) var isRecording = false
    /// What the recorder is doing: recording, paused, interrupted (and why), or stopped.
    @Published private(set) var recorder: RecorderState = .paused
    /// True while the latest save has failed.
    @Published private(set) var hasUnsavedChanges = false
    @Published private(set) var isFinished = false
    @Published private(set) var counter = "0:00"
    @Published private(set) var isLocationOn = false
    @Published private(set) var participants = ""
    @Published private(set) var startedLine = ""
    /// The title as the owner typed it: empty for a session that has not been named.
    @Published private(set) var titleAsTyped = ""
    @Published private(set) var notices: [SessionNotice] = []
    /// The note being written. It is shown in the note field, so its row is left off the page.
    @Published private(set) var draft = ""
    /// The clock time the note being written began, or empty.
    @Published private(set) var draftTime = ""

    private let controller: SessionController
    private var timer: Timer?

    private init(controller: SessionController, style: ClockStyle) {
        self.controller = controller
        self.style = style
        page = controller.page(style: style)
        publish()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    static func start(in root: URL, locationOn: Bool, standInLocation: Bool, style: ClockStyle) throws -> SessionModel {
        let controller = try SessionController.start(
            title: nil, participants: [], researcher: nil, device: ThisDevice.info, locationOn: locationOn, in: root,
            clock: SystemClock(), audio: StandInAudio(), location: StandInLocation(isOn: standInLocation),
            ids: RandomIdSource())
        return SessionModel(controller: controller, style: style)
    }

    static func open(_ folder: SessionFolder, locationOn: Bool, standInLocation: Bool, style: ClockStyle) throws -> SessionModel {
        let controller = try SessionController.open(
            folder, locationOn: locationOn, clock: SystemClock(), audio: StandInAudio(),
            location: StandInLocation(isOn: standInLocation), ids: RandomIdSource(),
            audioLength: { StandInAudio.length(of: $0) })
        return SessionModel(controller: controller, style: style)
    }

    // MARK: - What the owner does

    func pause() {
        controller.pause()
        publish()
    }

    func resume() {
        controller.resume()
        publish()
    }

    /// Ends the session and gives every file its checksum.
    func stop() {
        draft = ""
        controller.stop()
        publish()
    }

    /// The note field's text changed. A new line finishes the note and starts the next.
    func noteChanged(_ text: String) {
        guard text.contains("\n") else {
            draft = text
            controller.typing(text)
            publish()
            return
        }
        let parts = text.components(separatedBy: "\n")
        controller.typing(parts[0])
        controller.finishNote()
        let rest = parts.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
        draft = rest
        if !rest.isEmpty {
            controller.typing(rest)
        }
        publish()
    }

    func noteFinished() {
        controller.finishNote()
        draft = ""
        publish()
    }

    func takePhoto() {
        let request = controller.preparePhoto(fileExtension: StandInCamera.fileExtension)
        do {
            try StandInCamera.capture(request, style: style)
            controller.photoSaved(request)
        } catch {
            controller.photoFailed(request, reason: "The photo could not be saved.")
        }
        publish()
    }

    func setLocation(on: Bool) {
        controller.setLocation(on: on)
        publish()
    }

    func setTitle(_ title: String) {
        controller.setTitle(title)
        publish()
    }

    func clearNotices() {
        controller.clearNotices()
        publish()
    }

    /// Where a file listed on the page is on disk.
    func url(for file: String) -> URL {
        controller.folder.url(forRelativePath: file)
    }

    /// The screen is going away: save what is pending and stop the clock.
    func leave() {
        controller.finishNote()
        controller.saveIfNeeded()
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Inside

    private func tick() {
        controller.saveIfNeeded()
        // While interrupted, keep trying: the system does not always say when the microphone is free again.
        if case .interrupted = controller.recorderState {
            controller.interruptionEnded()
            publish()
            return
        }
        counter = Wording.length(milliseconds: controller.recordedMilliseconds)
        if hasUnsavedChanges != controller.hasUnsavedChanges {
            hasUnsavedChanges = controller.hasUnsavedChanges
        }
    }

    private func publish() {
        let whole = controller.page(style: style)
        let open = controller.openNoteId
        draftTime = whole.rows.first { $0.id == open }?.time ?? ""
        rows = whole.rows.filter { $0.id != open }
        page = whole
        isRecording = controller.isRecording
        recorder = controller.recorderState
        hasUnsavedChanges = controller.hasUnsavedChanges
        isFinished = controller.isFinished
        isLocationOn = controller.isLocationOn
        notices = controller.notices
        counter = Wording.length(milliseconds: controller.recordedMilliseconds)
        participants = controller.manifest.participants.joined(separator: ", ")
        titleAsTyped = controller.manifest.title
        let manifest = controller.manifest
        startedLine = "Since \(Wording.clock(manifest.createdAt, offset: manifest.utcOffset, style: style)) · \(Wording.zone(manifest.utcOffset))"
    }
}

extension SessionNotice {
    /// The sentence shown to the owner.
    var text: String {
        switch self {
        case .couldNotSave(let reason): return "The session could not be saved just now: \(reason). It will be tried again."
        case .couldNotRecord(let reason): return "Recording could not start: \(reason). It will start as soon as it can."
        case .couldNotTakePhoto(let reason): return reason
        case .filesMissing(let files):
            return "\(files.count == 1 ? "One file" : "\(files.count) files") this session listed \(files.count == 1 ? "is" : "are") no longer in its folder and \(files.count == 1 ? "has" : "have") been taken off the page: \(files.joined(separator: ", "))."
        case .filesNotListed(let files):
            return "\(files.count == 1 ? "One file" : "\(files.count) files") in this session's folder \(files.count == 1 ? "is" : "are") not on its page (saved just before the app was closed): \(files.joined(separator: ", ")). You can find \(files.count == 1 ? "it" : "them") in the Files app."
        case .recovered(let dropped):
            if dropped.isEmpty {
                return "The app was closed while this session was recording. Everything saved up to then has been kept."
            }
            return "The app was closed while this session was recording. \(dropped.count == 1 ? "One file" : "\(dropped.count) files") had not been saved and could not be kept: \(dropped.joined(separator: ", "))."
        }
    }
}
