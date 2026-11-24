import Foundation

/// Something the owner should be told. The screen shows these and clears them.
public enum SessionNotice: Equatable, Sendable {
    /// The last save failed. It is tried again on the next change.
    case couldNotSave(String)
    /// The microphone could not be had. Recording starts as soon as it can.
    case couldNotRecord(String)
    case couldNotTakePhoto(String)
    /// The session was cut off last time. These files never reached the disk and were taken off the page.
    case recovered(dropped: [String])
    /// Files the session listed are no longer in its folder. They were taken off the page.
    case filesMissing([String])
    /// Files in the session's folder that its page does not list: written just before the app was
    /// closed, and never recorded. They are left where they are.
    case filesNotListed([String])
}

/// What the recorder is doing, for the screen to show.
public enum RecorderState: Equatable, Sendable {
    case recording
    /// The owner paused it. Nothing is recorded until the owner resumes.
    case paused
    /// Recording stopped for a reason the owner did not choose (a phone call, no microphone), and
    /// will start again as soon as it can.
    case interrupted(String)
    /// The session was stopped.
    case stopped
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

    /// True from the moment recording is asked for until the owner pauses or stops. While it is
    /// true and nothing is recording, recording starts again as soon as it can.
    private var wantsToRecord = false
    /// Why recording stopped, when it was not the owner's doing.
    private var interruptionReason: String?
    /// Where the session began can be set only by the run that started it, with location on.
    private var canSetStartLocation = false
    private var needsSave = false
    private var lastSaveFailed = false
    private var lastSaveHost: Double = -.infinity
    /// Photos handed to the camera and not yet reported back.
    private var photosInFlight = Set<String>()
    /// The highest photo number ever handed out in this run, so a number is never used twice.
    private var highestPhotoNumber = 0

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

    public var recorderState: RecorderState {
        if isRecording { return .recording }
        if wantsToRecord { return .interrupted(interruptionReason ?? "the microphone is not available") }
        return lastRecordingMarker == .stopped ? .stopped : .paused
    }

    /// True while the latest save has failed. Unlike the notice, it stays true until a save works.
    public var hasUnsavedChanges: Bool { lastSaveFailed }

    /// The id of the note being written, if one is open. Its row is on the page like any other;
    /// a screen that shows the note in its own field leaves that row out.
    public var openNoteId: String? { writer.openNoteId }

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
    /// If the microphone cannot be had, the session still exists, and recording starts when it can.
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
        controller.canSetStartLocation = locationOn
        controller.wantsToRecord = true
        controller.beginSpan()
        if !locationOn {
            // Said on the page, so a reader can tell "off" from "no place was available".
            controller.attempt { try controller.timeline.setLocation(enabled: false, at: clock.now()) }
        }
        controller.save()
        return controller
    }

    /// Opens an existing session to read it, add to it, or resume recording.
    ///
    /// If it was cut off (the app was closed mid-recording) it is repaired first, and left
    /// complete: its files get their checksums, with no "Stopped" line, since the owner did not
    /// stop it. Anything it lists whose file is gone is taken off the page. A notice says what was done.
    ///
    /// Location is off if the session was switched off when it was last open, or if `locationOn`
    /// (the app's setting) is off now. `audioLength` reads an audio file's own length in
    /// milliseconds, or nil if it cannot.
    public static func open(_ folder: SessionFolder, locationOn: Bool, clock: any SessionClock,
                            audio: any AudioRecording, location: any LocationProviding, ids: any IdSource,
                            audioLength: (URL) -> Int?) throws -> SessionController {
        guard FileManager.default.fileExists(atPath: folder.sessionJSON.path) else {
            throw SessionControllerError.notASession(folder.url.lastPathComponent)
        }
        let loaded = try SessionStore.load(folder)
        let repaired = SessionStore.droppingMissingFiles(from: loaded, in: folder)
        let wasCutOff = SessionTimeline(resuming: loaded, ids: ids).needsRecovery
        var timeline = SessionTimeline(resuming: repaired.manifest, ids: ids)
        var notices: [SessionNotice] = []

        if wasCutOff {
            // Close what was left open, at the audio's own length.
            if timeline.needsRecovery {
                let openAudio = repaired.manifest.spans.last { $0.endedBy == nil }.map { folder.url(forRelativePath: $0.file) }
                try timeline.recoverAfterCrash(spanDurationMs: openAudio.flatMap(audioLength), at: clock.now())
            } else {
                // Everything that was open was among the files that never reached the disk.
                timeline.addCrashMarker()
            }
            notices.append(.recovered(dropped: repaired.dropped))
            let unlisted = unlistedMedia(in: folder, manifest: timeline.manifest)
            if !unlisted.isEmpty {
                notices.append(.filesNotListed(unlisted))
            }
        } else if !repaired.dropped.isEmpty {
            notices.append(.filesMissing(repaired.dropped))
        }

        // Location: what the session itself last said, unless the app's setting has been turned off since.
        var sessionSaysOn = true
        for item in timeline.manifest.items {
            if case .marker(_, let type, _) = item {
                if type == .locationOff { sessionSaysOn = false }
                if type == .locationOn { sessionSaysOn = true }
            }
        }
        let controller = SessionController(timeline: timeline, folder: folder, locationOn: sessionSaysOn && locationOn,
                                           clock: clock, audio: audio, location: location)
        controller.notices = notices
        var changed = !notices.isEmpty
        if sessionSaysOn && !locationOn {
            controller.attempt { try controller.timeline.setLocation(enabled: false, at: clock.now()) }
            changed = true
        }
        if wasCutOff {
            // Everything is closed now, so the session is made complete as it stands: it can be
            // copied out and checked without anyone having to open it and press Stop. The owner can
            // still resume it; that makes it unfinished again until the next Stop.
            controller.finish()
        } else if changed {
            controller.save()
        }
        return controller
    }

    // MARK: - Recording

    public func pause() {
        wantsToRecord = false
        interruptionReason = nil
        guard isRecording else { return }
        endSpan(by: .pause, detail: nil)
        renameFolderIfNeeded()
        save()
    }

    /// Starts recording again, into a new audio file. If the microphone cannot be had just now,
    /// recording starts as soon as it can (see `interruptionEnded`).
    public func resume() {
        guard !isRecording else { return }
        wantsToRecord = true
        beginSpan()
        save()
    }

    /// Ends the session: closes what is open, then gives every file its checksum. The session can
    /// still be read, added to, or resumed afterwards. Stopping a stopped session changes nothing.
    public func stop() {
        wantsToRecord = false
        interruptionReason = nil
        finishOpenNote()
        if isRecording {
            endSpan(by: .stop, detail: nil)
        } else if lastRecordingMarker != .stopped {
            attempt { try timeline.addMarker(.stopped, at: clock.now()) }
        }
        renameFolderIfNeeded()
        // Saved before the files are read through, so being closed during that leaves a session
        // that was plainly stopped, not one that looks cut off.
        save()
        finish()
    }

    /// Something else took the microphone: a phone call, another app.
    public func interruptionBegan(reason: String) {
        if wantsToRecord {
            interruptionReason = reason
        }
        guard isRecording else { return }
        endSpan(by: .interruption, detail: reason)
        save()
    }

    /// The microphone may be free again. Recording starts if it should be running and is not.
    /// Safe to call at any time, and more than once: the app calls it when it is told an
    /// interruption has ended, when it comes back to the front, and on a timer while interrupted.
    public func interruptionEnded() {
        guard wantsToRecord, !isRecording else { return }
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
        let wasOpen = writer.openNoteId
        attempt { try writer.typing(text, at: clock.now(), in: &timeline) }
        needsSave = true
        // A note's first character, and its removal, are saved at once; the rest at most every two seconds.
        if wasOpen != writer.openNoteId || clock.now().host - lastSaveHost >= Self.typingSaveInterval {
            save()
        }
    }

    /// The owner started a new paragraph or moved away from the note.
    public func finishNote() {
        finishOpenNote()
        save()
    }

    /// The owner changed an older note. Blank text removes it. An id that is not a note's does nothing.
    public func revise(noteId: String, text: String) {
        do {
            try writer.revise(id: noteId, text: text, at: clock.now(), in: &timeline)
        } catch TimelineError.noSuchItem {
            return
        } catch {
            notices.append(.couldNotSave(Self.plain(error)))
        }
        save()
    }

    // MARK: - Photos

    /// Call when the shutter is pressed. Gives the camera where to write the photo and what moment
    /// and place to write inside it. Nothing is listed in the session until `photoSaved`. Every
    /// request must be answered with exactly one `photoSaved` or `photoFailed`.
    ///
    /// The camera writes HEIC; `fileExtension` is for a stand-in that can only write something else.
    public func preparePhoto(fileExtension: String = "heic") -> PhotoRequest {
        let now = clock.now()
        // Counting what is listed and what is already on disk; then never below a number handed out before.
        let free = SessionStore.nextFile(.photo, ext: fileExtension, in: manifest, onDiskIn: folder)
        let digits = free.dropFirst("photos/photo-".count).prefix { $0.isNumber }
        let number = max(Int(digits) ?? 1, highestPhotoNumber + 1)
        highestPhotoNumber = number
        let name = String(number)
        let file = "photos/photo-" + String(repeating: "0", count: max(0, 4 - name.count)) + name + "." + fileExtension
        photosInFlight.insert(file)
        ensureSubfolder(of: file)
        return PhotoRequest(file: file, url: folder.url(forRelativePath: file), moment: now,
                            place: Place.stamp(from: location.latest, enabled: isLocationOn, now: now.wall))
    }

    /// The camera wrote the photo. It is placed where it was taken, even if recording has paused
    /// since. A finished session stays finished: the new photo is given its checksum at once.
    public func photoSaved(_ request: PhotoRequest) {
        guard photosInFlight.remove(request.file) != nil else { return }      // answered already
        guard FileManager.default.fileExists(atPath: folder.url(forRelativePath: request.file).path) else {
            notices.append(.couldNotTakePhoto("The photo was not saved."))
            renameFolderIfNeeded()
            return
        }
        let wasFinished = isFinished
        attempt { _ = try timeline.addPhoto(file: request.file, gps: request.place, at: request.moment) }
        if wasFinished, let sum = try? SHA256Hex.ofFile(at: folder.url(forRelativePath: request.file)) {
            timeline.setChecksums([request.file: sum])
        }
        renameFolderIfNeeded()
        save()
    }

    public func photoFailed(_ request: PhotoRequest, reason: String) {
        guard photosInFlight.remove(request.file) != nil else { return }
        notices.append(.couldNotTakePhoto(reason))
        renameFolderIfNeeded()
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

    /// Call when the location chip has a reading. Sets where the session began, once: only in the
    /// run that started the session with location on, and only within two minutes of the start.
    public func locationFixArrived() {
        guard canSetStartLocation, isLocationOn, manifest.startLocation == nil else { return }
        let now = clock.now().wall
        let elapsed = now.millisecondsSince1970 - manifest.createdAt.millisecondsSince1970
        guard (0...Self.startLocationWindowMs).contains(elapsed),
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

    /// Saves anything not yet saved. Call it on a timer and when the app leaves the screen.
    public func saveIfNeeded() {
        if needsSave { save() }
    }

    // MARK: - Inside

    /// One line: blank space at the ends removed, and any run of blank space or new lines inside made one space.
    private static func tidy(_ title: String) -> String {
        title.split { $0.isWhitespace }.joined(separator: " ")
    }

    /// An error as a few plain words. Raw error text is never shown to the owner.
    private static func plain(_ error: Error) -> String {
        if let store = error as? SessionStoreError {
            switch store {
            case .unwritable(let why): return "its record could not be written: \(why)"
            case .missingFile(let file): return "\(file) is missing"
            case .folderExists(let name): return "a folder named \(name) is already there"
            case .inconsistent(let problems):
                return problems.first.map { "\($0.path) \($0.message)" } ?? "its record does not add up"
            }
        }
        if error is TimelineError {
            return "something unexpected happened"
        }
        return "the session's folder could not be written to"
    }

    /// The latest thing the page says about recording.
    private var lastRecordingMarker: MarkerType? {
        for item in manifest.items.reversed() {
            if case .marker(_, let type, _) = item, type != .locationOff, type != .locationOn {
                return type
            }
        }
        return nil
    }

    /// Media files in the session's own subfolders that the manifest does not list.
    private static func unlistedMedia(in folder: SessionFolder, manifest: Manifest) -> [String] {
        let listed = Set(SessionStore.listedFiles(in: manifest))
        return SessionCheck.filesOnDisk(under: folder.url).filter { path in
            SessionStore.subfolders.contains { path.hasPrefix($0 + "/") } && !listed.contains(path) && !SessionCheck.isMacLitter(path)
        }
    }

    /// Runs a change to the timeline that should not be able to fail here. If it does, the owner is told.
    private func attempt(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            notices.append(.couldNotSave(Self.plain(error)))
        }
    }

    private func ensureSubfolder(of file: String) {
        let directory = folder.url(forRelativePath: file).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Starts a new audio file and opens a span for it. Returns false, with a notice, if the
    /// microphone cannot be had; `wantsToRecord` is left as it is, so it is tried again.
    @discardableResult
    private func beginSpan() -> Bool {
        let file = SessionStore.nextFile(.audio, ext: "m4a", in: manifest, onDiskIn: folder)
        ensureSubfolder(of: file)
        let began: Moment?
        do {
            began = try audio.start(writingTo: folder.url(forRelativePath: file))
        } catch {
            if notices.last != .couldNotRecord("the microphone is not available") {
                notices.append(.couldNotRecord("the microphone is not available"))
            }
            return false
        }
        // The session is being added to: a checksum must never sit beside a file that may change.
        timeline.clearChecksums()
        attempt { _ = try timeline.startRecording(file: file, at: began ?? clock.now()) }
        interruptionReason = nil
        return true
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
        guard !isRecording, photosInFlight.isEmpty else { return }
        if let renamed = try? SessionStore.renameToMatchTitle(folder, manifest: manifest) {
            folder = renamed
        }
    }

    /// Takes anything whose file has gone off the page, and says so.
    private func dropMissingFiles() {
        guard !isRecording else { return }
        let repaired = SessionStore.droppingMissingFiles(from: manifest, in: folder)
        guard !repaired.dropped.isEmpty else { return }
        attempt { try timeline.adopt(repaired: repaired.manifest) }
        notices.append(.filesMissing(repaired.dropped))
    }

    /// Gives every file its checksum and checks the session is complete. A listed file that has
    /// gone is taken off the page first, so one missing file can never leave a session that cannot
    /// be finished. On any other failure the session stays unfinished and the owner is told.
    private func finish() {
        dropMissingFiles()
        guard !isFinished else {
            save()
            return
        }
        do {
            timeline.setChecksums(try SessionStore.checksums(for: manifest, in: folder))
            if let first = manifest.problems(finished: true).first {
                timeline.clearChecksums()
                notices.append(.couldNotSave("the session could not be finished: \(first.path) \(first.message)"))
            }
        } catch {
            timeline.clearChecksums()
            notices.append(.couldNotSave("the session could not be finished: \(Self.plain(error))"))
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
                notices.append(.couldNotSave(Self.plain(error)))
            }
            lastSaveFailed = true
        }
    }
}
