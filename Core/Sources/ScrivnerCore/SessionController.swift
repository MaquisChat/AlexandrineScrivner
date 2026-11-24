import Foundation

/// Something the owner should be told. The screen shows these and clears them.
public enum SessionNotice: Equatable, Sendable {
    /// The last save failed. It is tried again on the next change.
    case couldNotSave(String)
    /// The microphone could not be had.
    case couldNotRecord(String)
    case couldNotTakePhoto(String)
    /// The session was cut off last time. These files never reached the disk and were dropped.
    case recovered(dropped: [String])
}

public enum SessionControllerError: Error, Equatable {
    case notASession(String)
}

/// Runs one session: owns its timeline and its folder, and is the only thing the screens call.
///
/// It reaches the device through `SessionClock`, `AudioRecording` and `LocationProviding`. The
/// camera is driven by the screen, in two steps: `preparePhoto()` when the shutter is pressed, then
/// `photoSaved` or `photoFailed` when the camera has finished. Use it from one thread.
public final class SessionController {
    private var timeline: SessionTimeline
    private var writer = NoteWriter()
    private let clock: any SessionClock
    private let audio: any AudioRecording
    private let location: any LocationProviding

    public private(set) var folder: SessionFolder
    public private(set) var isLocationOn: Bool
    public private(set) var notices: [SessionNotice] = []

    /// True when recording stopped because of an interruption, not because the owner paused.
    private var stoppedByInterruption = false
    private var needsSave = false
    private var lastSaveFailed = false
    private var lastSaveHost: Double = -.infinity
    /// Photo numbers handed out but not yet listed, so two quick photos never share a name.
    private var photosPrepared = 0

    /// Typing is saved at most this often; everything else is saved as it happens.
    static let typingSaveInterval: Double = 2
    /// A first location reading later than this after the start is no longer where the session began.
    static let startLocationWindowMs: Int64 = 120_000

    public var manifest: Manifest { timeline.manifest }
    public var isRecording: Bool { timeline.isRecording }

    /// No span is open and every file has its checksum: the session can be shared as it stands.
    public var isFinished: Bool {
        !manifest.spans.contains { $0.endedBy == nil }
            && !SessionCheck.listedFiles(in: manifest).contains { $0.sha256 == nil }
    }

    /// The words of the note being written, if one is open.
    public var openNoteText: String? {
        guard let open = writer.openNoteId else { return nil }
        for item in manifest.items {
            if case .text(let placement, let text, _) = item, placement.id == open { return text }
        }
        return nil
    }

    private init(timeline: SessionTimeline, folder: SessionFolder, locationOn: Bool,
                 clock: any SessionClock, audio: any AudioRecording, location: any LocationProviding) {
        self.timeline = timeline
        self.folder = folder
        self.isLocationOn = locationOn
        self.clock = clock
        self.audio = audio
        self.location = location
    }

    // MARK: - Starting and opening

    /// Starts a new session and starts recording at once. A blank title leaves the session untitled.
    /// If the microphone cannot be had, the session still exists, not recording, with a notice.
    public static func start(title: String?, participants: [String], researcher: String?, device: DeviceInfo,
                             locationOn: Bool, in root: URL, clock: any SessionClock, audio: any AudioRecording,
                             location: any LocationProviding, ids: any IdSource) throws -> SessionController {
        let now = clock.now()
        let timeline = SessionTimeline(title: tidy(title ?? ""), participants: participants, researcher: researcher,
                                       device: device,
                                       startLocation: Place.stamp(from: location.latest, enabled: locationOn, now: now.wall),
                                       at: now, ids: ids)
        let folder = try SessionStore.create(timeline.manifest, in: root)
        let controller = SessionController(timeline: timeline, folder: folder, locationOn: locationOn,
                                           clock: clock, audio: audio, location: location)
        controller.beginSpan()
        controller.save()
        return controller
    }

    /// Opens an existing session to read it, add to it, or resume recording. If it was cut off
    /// (the app was killed mid-recording), it is repaired first and a notice says so.
    /// `audioLength` reads an audio file's own length in milliseconds, or nil if it cannot.
    public static func open(_ folder: SessionFolder, locationOn: Bool, clock: any SessionClock,
                            audio: any AudioRecording, location: any LocationProviding, ids: any IdSource,
                            audioLength: (URL) -> Int?) throws -> SessionController {
        guard FileManager.default.fileExists(atPath: folder.sessionJSON.path) else {
            throw SessionControllerError.notASession(folder.url.lastPathComponent)
        }
        let loaded = try SessionStore.load(folder)
        var timeline = SessionTimeline(resuming: loaded, ids: ids)
        guard timeline.needsRecovery else {
            return SessionController(timeline: timeline, folder: folder, locationOn: locationOn,
                                     clock: clock, audio: audio, location: location)
        }

        // Cut off last time. Drop what never reached the disk, then close what was left open.
        let repaired = SessionStore.droppingMissingFiles(from: loaded, in: folder)
        timeline = SessionTimeline(resuming: repaired.manifest, ids: ids)
        let now = clock.now()
        if timeline.needsRecovery {
            let openAudio = repaired.manifest.spans.last { $0.endedBy == nil }.map { folder.url(forRelativePath: $0.file) }
            try timeline.recoverAfterCrash(spanDurationMs: openAudio.flatMap(audioLength), at: now)
        } else {
            // Everything that was open was among the files that never reached the disk.
            try timeline.addMarker(.interrupted, detail: "crash-recovered", at: now)
        }
        let controller = SessionController(timeline: timeline, folder: folder, locationOn: locationOn,
                                           clock: clock, audio: audio, location: location)
        controller.notices.append(.recovered(dropped: repaired.dropped))
        controller.save()
        return controller
    }

    // MARK: - Recording

    public func pause() {
        stoppedByInterruption = false
        guard isRecording else { return }
        endSpan(by: .pause, detail: nil)
        renameFolderIfNeeded()
        save()
    }

    /// Starts recording again, into a new audio file. A finished session becomes unfinished again.
    public func resume() {
        guard !isRecording else { return }
        stoppedByInterruption = false
        timeline.clearChecksums()
        beginSpan()
        save()
    }

    /// Ends the session: closes what is open, then gives every file its checksum. The session can
    /// still be read, added to, or resumed afterwards.
    public func stop() {
        stoppedByInterruption = false
        finishOpenNote()
        if isRecording {
            endSpan(by: .stop, detail: nil)
        } else {
            attempt { try timeline.addMarker(.stopped, at: clock.now()) }
        }
        renameFolderIfNeeded()
        finish()
    }

    /// Something else took the microphone: a phone call, another app.
    public func interruptionBegan(reason: String) {
        guard isRecording else { return }
        endSpan(by: .interruption, detail: reason)
        stoppedByInterruption = true
        save()
    }

    /// The microphone is free again. Recording resumes only if the interruption, not the owner, stopped it.
    public func interruptionEnded() {
        guard stoppedByInterruption, !isRecording else { return }
        stoppedByInterruption = false
        beginSpan()
        save()
    }

    /// Closed spans by their audio's own length, plus the open one so far by the clock.
    public var recordedMilliseconds: Int {
        let closed = manifest.spans.reduce(0) { $0 + ($1.durationMs ?? 0) }
        return closed + (timeline.openSpanElapsedMs(at: clock.now()) ?? 0)
    }

    // MARK: - Notes

    /// The note being written now reads `text`.
    public func typing(_ text: String) {
        let wasOpen = writer.openNoteId != nil
        attempt { try writer.typing(text, at: clock.now(), in: &timeline) }
        needsSave = true
        // A note's first character, and its removal, are saved at once; the rest at most every two seconds.
        if wasOpen != (writer.openNoteId != nil) || clock.now().host - lastSaveHost >= Self.typingSaveInterval {
            save()
        }
    }

    /// The owner started a new paragraph or moved away from the note.
    public func finishNote() {
        finishOpenNote()
        save()
    }

    /// The owner changed an older note. Blank text removes it.
    public func revise(noteId: String, text: String) {
        attempt { try writer.revise(id: noteId, text: text, at: clock.now(), in: &timeline) }
        save()
    }

    // MARK: - Photos

    /// Call when the shutter is pressed. Gives the camera where to write the photo and what moment
    /// and place to write inside it. Nothing is listed in the session until `photoSaved`.
    /// The camera writes HEIC; `fileExtension` is for a stand-in that can only write something else.
    public func preparePhoto(fileExtension: String = "heic") -> PhotoRequest {
        let now = clock.now()
        let listed = SessionStore.nextFile(.photo, ext: fileExtension, in: manifest)
        // "photos/photo-0007.heic" → 7, then skip past numbers already handed out.
        let digits = listed.dropFirst("photos/photo-".count).prefix { $0.isNumber }
        let number = (Int(digits) ?? 1) + photosPrepared
        photosPrepared += 1
        let name = String(number)
        let file = "photos/photo-" + String(repeating: "0", count: max(0, 4 - name.count)) + name + "." + fileExtension
        return PhotoRequest(file: file, url: folder.url(forRelativePath: file), moment: now,
                            place: Place.stamp(from: location.latest, enabled: isLocationOn, now: now.wall))
    }

    /// The camera wrote the photo. It is placed where it was taken, even if recording has paused since.
    public func photoSaved(_ request: PhotoRequest) {
        photosPrepared = max(0, photosPrepared - 1)
        guard FileManager.default.fileExists(atPath: folder.url(forRelativePath: request.file).path) else {
            notices.append(.couldNotTakePhoto("the photo was not saved"))
            return
        }
        attempt { _ = try timeline.addPhoto(file: request.file, gps: request.place, at: request.moment) }
        timeline.clearChecksums()
        save()
    }

    public func photoFailed(_ request: PhotoRequest, reason: String) {
        photosPrepared = max(0, photosPrepared - 1)
        notices.append(.couldNotTakePhoto(reason))
    }

    // MARK: - Session details

    /// Switches location stamping. Turning it off stops every further stamp and writes a marker;
    /// nothing already saved is removed.
    public func setLocation(on: Bool) {
        guard on != isLocationOn else { return }
        isLocationOn = on
        attempt { try timeline.setLocation(enabled: on, at: clock.now()) }
        save()
    }

    /// Call when the location chip has a reading. Sets where the session began, once, if location
    /// is on and the reading comes within two minutes of the start.
    public func locationFixArrived() {
        guard isLocationOn, manifest.startLocation == nil else { return }
        let now = clock.now().wall
        guard now.millisecondsSince1970 - manifest.createdAt.millisecondsSince1970 <= Self.startLocationWindowMs,
              let place = Place.stamp(from: location.latest, enabled: true, now: now) else { return }
        timeline.setStartLocation(place)
        save()
    }

    /// Renames the session. Its folder follows as soon as nothing is being recorded into it.
    public func setTitle(_ title: String) {
        timeline.setTitle(Self.tidy(title))
        renameFolderIfNeeded()
        save()
    }

    /// Participant codes, typed as one line: separated by commas or spaces.
    public func setParticipants(_ text: String) {
        let codes = text.split { $0 == "," || $0.isWhitespace }.map(String.init)
        timeline.setParticipants(codes)
        save()
    }

    public func page(style: ClockStyle) -> Page {
        Page(manifest, style: style)
    }

    public func clearNotices() {
        notices.removeAll()
    }

    /// Saves anything typed since the last save. Call it on a timer and when the app leaves the screen.
    public func saveIfNeeded() {
        if needsSave { save() }
    }

    // MARK: - Inside

    private static func tidy(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs a change to the timeline that should not be able to fail here. If it does, the owner is told.
    private func attempt(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            notices.append(.couldNotSave("\(error)"))
        }
    }

    private func beginSpan() {
        let file = SessionStore.nextFile(.audio, ext: "m4a", in: manifest)
        do {
            try audio.start(writingTo: folder.url(forRelativePath: file))
        } catch {
            notices.append(.couldNotRecord("\(error)"))
            return
        }
        attempt { _ = try timeline.startRecording(file: file, at: clock.now()) }
    }

    private func endSpan(by end: SpanEnd, detail: String?) {
        let length = audio.stop()
        attempt { try timeline.endRecording(by: end, detail: detail, audioDurationMs: length, at: clock.now()) }
    }

    private func finishOpenNote() {
        attempt { try writer.finish(in: &timeline) }
        needsSave = true
    }

    /// The folder is named after the title, but is only renamed while nothing is being written into it.
    private func renameFolderIfNeeded() {
        guard !isRecording, photosPrepared == 0 else { return }
        if let renamed = try? SessionStore.renameToMatchTitle(folder, manifest: manifest) {
            folder = renamed
        }
    }

    /// Gives every file its checksum and checks the session is complete. On failure the session
    /// stays unfinished and the owner is told.
    private func finish() {
        do {
            timeline.setChecksums(try SessionStore.checksums(for: manifest, in: folder))
            let problems = manifest.problems(finished: true)
            if let first = problems.first {
                timeline.clearChecksums()
                notices.append(.couldNotSave("the session could not be finished: \(first.path) \(first.message)"))
            }
        } catch {
            timeline.clearChecksums()
            notices.append(.couldNotSave("the session could not be finished: \(error)"))
        }
        save()
    }

    private func save() {
        do {
            try SessionStore.save(manifest, to: folder)
            needsSave = false
            lastSaveFailed = false
            lastSaveHost = clock.now().host
        } catch {
            needsSave = true
            if !lastSaveFailed {
                notices.append(.couldNotSave("\(error)"))
            }
            lastSaveFailed = true
        }
    }
}
