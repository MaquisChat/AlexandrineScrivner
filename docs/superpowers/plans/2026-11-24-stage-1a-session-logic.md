# Stage 1a: The Logic Behind the iPhone App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Everything the iPhone app does that is not a screen, a microphone, a camera or a location chip, built and tested without a device: running a session from start to stop through small interfaces to the hardware, the page as the screens will show it, the session list, and the checks and warnings around them.

**Architecture:** One `SessionController` in `ScrivnerCore` owns the session's timeline and its folder, and talks to the hardware through four small protocols (clock, audio, camera, location). In tests those are fakes; in the app (stage 1b and 1c) they are thin adapters around Apple's frameworks. Screens never touch the timeline or the folder directly: they call the controller and draw the `Page` it gives back. Everything else here is a pure function over values.

**Tech Stack:** Swift 6, Foundation only, XCTest. Runs with `swift test` on Linux and on a Mac.

**Spec:** `docs/superpowers/specs/2026-11-23-field-notebook-recorder-design.md`, section 5 (what the app does) and section 7 (two layers, crash-safe audio).

## What this plan leaves to later plans

- **Stage 1b, the screens:** SwiftUI views over `SessionController` and `Page`, both layouts and the switch, the cover, the session list, sharing a zip, with fake hardware so they run in the simulator.
- **Stage 1c, the hardware:** the real audio, camera and location adapters, background and lock behaviour, file protection, notifications. The audio adapter waits for the stage 0 device results (ADR 0001).

## Global Constraints

- `ScrivnerCore` stays Foundation only, no package dependencies, Swift language mode 6, and must build for iOS.
- The session folder format is version 1 as defined in `format/`. Nothing here changes it. App-only state (when a session was exported) is kept outside the session folder.
- Positions on the audio come from the monotonic clock (`Moment.host`), never from wall-clock subtraction.
- Times shown on the page are clock time in the device's local time zone at the moment the thing was made (its own `utcOffset`), `10:43` in 24-hour style or `10:43 am` in 12-hour style. Seconds are stored, not shown (spec 5.3).
- Pause means the microphone is off. Notes and photos still work while paused (spec 5.1).
- Location: on for a new session when the setting is on; switching it off mid-session stops every further stamp and writes a marker; nothing already saved is removed (spec 5.7).
- The app never deletes a session's files except through an explicit delete of the whole session.
- Wording shown to the owner is plain English and is fixed in the tests below.
- Work on branch `stage-1a`, cut from `checker`.

## Review Focus

Inputs the spec implies that are most likely to bite, each pinned by a test in the task named:

1. **The app is killed mid-recording and reopened.** The session must come back usable: missing files dropped, the open span closed at the audio's real length, a marker on the page, and recording able to resume. `testReopeningAfterTheAppWasKilled` (Task 5).
2. **A phone call interrupts recording, then ends.** One span closes with a reason, a new one opens when the microphone returns, and nothing typed in between is lost or placed on audio that does not exist. `testInterruptionClosesTheSpanAndResumeOpensANewOne` (Task 4).
3. **The disk fills, or a save fails, mid-session.** The owner is told, the last good `session.json` survives, and recording is not silently dropped. `testASaveThatFailsIsReportedAndRetried` (Task 4).
4. **The owner types, deletes everything, and types again; or leaves a note empty.** No empty notes on the page, no stale times. `testAnEmptiedNoteIsRemoved`, `testANoteKeepsTheTimeOfItsFirstCharacter` (Task 3).
5. **Location is switched off in the middle of a session.** No photo taken afterwards carries a place, even if the location chip still has a fresh fix. `testNoPlaceAfterLocationIsSwitchedOff` (Task 4).
6. **Midnight and a time-zone change during a session.** The page shows each thing at its own local time. `testEachRowShowsItsOwnLocalTime` (Task 2).

---

### Task 1: Small changes to the timeline that the controller needs

**Files:**
- Modify: `Core/Sources/ScrivnerCore/SessionTimeline.swift`
- Test: `Core/Tests/ScrivnerCoreTests/SessionTimelineTests.swift`

**Interfaces:**
- Produces:
  - `mutating func setText(id: String, text: String) throws`: changes a note's words without recording a later edit. For a note that is still being written.
  - `mutating func removeItem(id: String) throws`: removes a note, photo, clip or handwriting block. Markers cannot be removed (`TimelineError.cannotRemoveMarker`). Throws `noSuchItem` for an unknown id.
  - `var openSpanId: String? { get }`: the span being recorded, if any.

- [x] **Step 1: Failing tests**

```swift
func testSetTextDoesNotCountAsALaterEdit()      // addText, setText → text changed, modifiedAt nil; then editText → modifiedAt set
func testRemoveItem()                           // remove a text and a photo → gone; removing a marker throws .cannotRemoveMarker; unknown id throws .noSuchItem; needsRecovery timeline throws .needsRecovery
func testOpenSpanId()                           // nil before recording, the span's id while recording, nil after pause
```

- [x] **Step 2: Run; expect a build failure naming `setText`.**
- [x] **Step 3: Implement.**
- [x] **Step 4: `swift test --package-path Core`; all pass.**
- [x] **Step 5: Commit.** `feat(core): timeline changes the session controller needs`

---

### Task 2: The page, as the screens show it

**Files:**
- Create: `Core/Sources/ScrivnerCore/Wording.swift`, `Core/Sources/ScrivnerCore/Page.swift`
- Modify: `Core/Sources/ScrivnerCore/NotesMarkdown.swift` (use `Wording` for marker text; output unchanged)
- Test: `Core/Tests/ScrivnerCoreTests/PageTests.swift`

**Interfaces:**
- Produces:

```swift
public enum ClockStyle: Sendable { case twentyFourHour, twelveHour }

public enum Wording {
    /// "10:43" or "10:43 am"; midnight is "00:05" or "12:05 am"; noon is "12:00" or "12:00 pm".
    public static func clock(_ instant: Instant, offset: UTCOffset, style: ClockStyle) -> String
    /// "UTC+5:45", "UTC-9:30", "UTC+0", "UTC+1".
    public static func zone(_ offset: UTCOffset) -> String
    /// "Recording started", "Paused", "Resumed", "Stopped", "Interrupted (phone call)", "Location off", "Location on".
    /// A crash is "Interrupted (the app was closed unexpectedly)".
    public static func marker(_ type: MarkerType, detail: String?) -> String
    /// A length: "0:48", "12:07", "1:02:03".
    public static func length(milliseconds: Int) -> String
}

public struct PageRow: Equatable, Sendable, Identifiable {
    public enum Content: Equatable, Sendable {
        case marker(String)                                   // ready to show, e.g. "Recording started · local time, UTC+5:45"
        case text(String, edited: Bool)
        case photo(file: String)
        case video(file: String, length: String?, note: String?)   // note: "no sound", "still recording", "ended when the phone locked", …
        case ink(file: String)
    }
    public let id: String
    public let time: String          // the clock time to show beside or under it
    public let content: Content
    public let isOnAudio: Bool       // false when made while nothing was recording
}

public struct Page: Equatable, Sendable {
    public let title: String
    public let rows: [PageRow]
    public init(_ manifest: Manifest, style: ClockStyle)
}
```

Marker rows for recording started, resumed, paused, stopped and interrupted carry the time zone, as spec 5.3 asks: `Recording started · local time, UTC+5:45`. Location markers do not.

Clip notes, joined with `, ` when more than one applies: `still recording` (no `endedBy`); `no sound`; `ended when the app left the screen` (background); `ended when the phone locked` (lock); `ended by an interruption`; `ended when the session stopped` (stop). A clip ended by the owner has no ending note.

- [x] **Step 1: Failing tests**

```swift
func testClockStyles()                 // 04:57:10.120Z at +05:45 → "10:42" / "10:42 am"; 18:20Z at +05:45 → "00:05" / "12:05 am"; 06:15Z at +05:45 → "12:00" / "12:00 pm"; 13:00Z at -09:30 → "03:30" / "3:30 am"
func testZones()                       // +05:45 → "UTC+5:45"; -09:30 → "UTC-9:30"; 0 → "UTC+0"; +01:00 → "UTC+1"
func testLengths()                     // 48_000 → "0:48"; 727_000 → "12:07"; 3_723_000 → "1:02:03"; 999 → "0:01"; 0 → "0:00"
func testThePageOfTheWorkedExample()   // Page(ExampleSession manifest, .twentyFourHour): 13 rows; times ["10:42","10:43","10:45","10:45","10:49","10:50","10:51","10:51","10:52","10:52","10:53","10:54","10:55"];
                                       // row 0 == .marker("Recording started · local time, UTC+5:45"); row 4 == .video(file: "video/clip-0001.mov", length: "0:48", note: nil);
                                       // row 7 == .marker("Location off"); row 9 == .video(file: "video/clip-0002.mov", length: "0:12", note: "no sound"); rows 8 and 9 have isOnAudio false
func testEachRowShowsItsOwnLocalTime() // two notes one minute apart, the second at another offset (+05:30) and past midnight → each row's time uses its own offset
func testEditedAndUnfinishedThings()   // a text with modifiedAt → .text(_, edited: true); an open clip → note "still recording"; a clip ended by lock while paused → "no sound, ended when the phone locked"
func testNotesMarkdownIsUnchanged()    // NotesMarkdown.render(example manifest) equals the committed format/examples/…/notes.md
func testCrashMarkerWording()          // .interrupted with detail "crash-recovered" → "Interrupted (the app was closed unexpectedly) · local time, UTC+5:45"
```

`notes.md` keeps saying `Interrupted (crash-recovered)` today; this task changes it to the same wording as the page, and the example and `format/` files are regenerated only if their text changes (the example has no crash marker, so they should not).

- [x] **Step 2: Run; expect `cannot find 'Wording' in scope`.**
- [x] **Step 3: Implement.**
- [x] **Step 4: All tests pass; `(cd format && npm run validate)` still OK.**
- [x] **Step 5: Commit.** `feat(core): the page as the screens show it`

---

### Task 3: Writing a note

**Files:**
- Create: `Core/Sources/ScrivnerCore/NoteWriter.swift`
- Test: `Core/Tests/ScrivnerCoreTests/NoteWriterTests.swift`

**Interfaces:**
- Consumes: `SessionTimeline.addText`, `setText`, `editText`, `removeItem` (Task 1).
- Produces:

```swift
/// Turns what the owner types into notes on the timeline.
/// A note begins at its first character and ends when the owner starts a new paragraph or moves away.
public struct NoteWriter: Sendable {
    public private(set) var openNoteId: String?
    public init()
    /// The text of the note being written is now `text`. Creates the note on its first character.
    /// Leading and trailing blank space is kept while writing.
    public mutating func typing(_ text: String, at moment: Moment, in timeline: inout SessionTimeline) throws
    /// The owner started a new paragraph or moved away. An empty or all-blank note is removed.
    /// The note's text is trimmed of blank space at both ends.
    public mutating func finish(in timeline: inout SessionTimeline) throws
    /// The owner changed an older note. Empty text removes it. Otherwise it keeps its time and records when it was changed.
    public func revise(id: String, text: String, at moment: Moment, in timeline: inout SessionTimeline) throws
}
```

- [x] **Step 1: Failing tests**

```swift
func testANoteKeepsTheTimeOfItsFirstCharacter()   // typing("P") at 65 s, typing("P-014 has run") at 70 s, finish → one text, at = t0+65 s, offsetMs 65_000, modifiedAt nil
func testANewParagraphStartsANewNote()            // type, finish, type again at 90 s → two texts with their own times; openNoteId differs
func testAnEmptiedNoteIsRemoved()                 // typing("x"), typing(""), finish → no text items; typing("  \n ") then finish → none
func testTypingAgainAfterEmptyingStartsAFreshNote() // typing("x") at 10 s, typing("") at 12 s, typing("y") at 30 s, finish → one text "y" at 30 s
func testFinishTrimsTheEnds()                     // "  hello \n" → "hello"
func testRevisingAnOlderNote()                    // revise at 500 s → same at/offsetMs, modifiedAt = t0+500 s; revise with "" → removed
func testFinishWithNothingOpenDoesNothing()
```

- [x] **Step 2: Run; expect `cannot find 'NoteWriter' in scope`.**
- [x] **Step 3: Implement.** While a note is open and its text becomes empty, the note is removed at once and `openNoteId` cleared, so typing again starts a fresh note with a fresh time.
- [x] **Step 4: All tests pass.**
- [x] **Step 5: Commit.** `feat(core): writing notes`

---

### Task 4: The session controller

**Files:**
- Create: `Core/Sources/ScrivnerCore/Hardware.swift`, `Core/Sources/ScrivnerCore/SessionController.swift`
- Test: `Core/Tests/ScrivnerCoreTests/Fakes.swift`, `Core/Tests/ScrivnerCoreTests/SessionControllerTests.swift`

**Interfaces:**
- Consumes: Tasks 1 to 3, `SessionStore`, `SessionFolder`.
- Produces, in `Hardware.swift`:

```swift
public protocol SessionClock: Sendable { func now() -> Moment }

public protocol AudioRecording: AnyObject {
    /// Starts writing a new audio file. Throws if the microphone cannot be had.
    func start(writingTo url: URL) throws
    /// Stops and returns the finished file's own length in milliseconds, or nil if it cannot be read.
    func stop() -> Int?
}

public struct LocationFix: Equatable, Sendable {
    public var lat, lon: Double
    public var alt: Double?
    public var horizontalAccuracyM: Double       // negative means the reading is not valid
    public var verticalAccuracyM: Double?        // negative or nil means the altitude is not valid
    public var at: Instant
}
public protocol LocationProviding: AnyObject { var latest: LocationFix? { get } }

public protocol PhotoCapturing: AnyObject {
    /// Takes a photo and writes it, with its time and place inside the file, to `url`.
    func capture(to url: URL, at moment: Moment, place: GeoPoint?) throws
}

public enum Place {
    /// The place to stamp, or nil: location off, no fix, a fix that is not valid, or one older than 60 s.
    /// An invalid altitude is dropped; the accuracy is the horizontal one.
    public static func stamp(from fix: LocationFix?, enabled: Bool, now: Instant) -> GeoPoint?
}
```

In `SessionController.swift`:

```swift
public enum SessionNotice: Equatable, Sendable {
    case couldNotSave(String)            // the last save failed; it will be tried again on the next change
    case couldNotRecord(String)          // the microphone could not be had
    case couldNotTakePhoto(String)
    case recovered(dropped: [String])    // the session was cut off last time; these files never reached the disk
}

public final class SessionController {
    public private(set) var manifest: Manifest          // what is on disk, or about to be
    public private(set) var folder: SessionFolder
    public private(set) var isRecording: Bool
    public private(set) var isLocationOn: Bool
    public private(set) var notices: [SessionNotice]     // newest last; the screen shows and clears them
    public func clearNotices()

    /// Starts a new session and, as spec 5.1 says, starts recording at once.
    public static func start(title: String?, participants: [String], researcher: String?, device: DeviceInfo,
                             locationOn: Bool, in root: URL, clock: any SessionClock, audio: any AudioRecording,
                             camera: any PhotoCapturing, location: any LocationProviding, ids: any IdSource) throws -> SessionController
    /// Opens an existing session to read it, add to it, or resume recording. Repairs it first if it was cut off.
    public static func open(_ folder: SessionFolder, locationOn: Bool, clock: any SessionClock, audio: any AudioRecording,
                            camera: any PhotoCapturing, location: any LocationProviding, ids: any IdSource,
                            audioLength: (URL) -> Int?) throws -> SessionController

    public func pause()
    public func resume()
    public func stop()                                   // closes the span, finishes the session (checksums), leaves it open for reading
    public func interruptionBegan(reason: String)        // e.g. "phone call"
    public func interruptionEnded()                      // resumes if the interruption, not the owner, stopped it
    public func typing(_ text: String)
    public func finishNote()
    public func revise(noteId: String, text: String)
    public func takePhoto()
    public func setLocation(on: Bool)
    public func setTitle(_ title: String)                // also renames the folder
    public func setParticipants(_ text: String)          // split on commas and blank space
    public func locationFixArrived()                     // sets the session's start location once, if it has none and location is on
    public func page(style: ClockStyle) -> Page
    public var recordedMilliseconds: Int { get }         // closed spans plus the open one so far
}
```

Rules:

- A title of nil or blank becomes the local date and start time: `2026-11-23 10:42` (spec 5.1).
- Every method that changes the session saves it (`SessionStore.save`). A save that fails adds `couldNotSave` with the reason and is tried again on the next change; nothing else is undone.
- `start`: creates the folder, starts audio into `SessionStore.nextFile(.audio, ext: "m4a", …)`, opens the span. If the microphone cannot be had, the session still exists, paused, with `couldNotRecord`.
- `pause`, `stop`, `interruptionBegan`: `audio.stop()` gives the file's length, which closes the span (`endRecording(by:detail:audioDurationMs:at:)`).
- `resume`, `interruptionEnded`: a new audio file and a new span. `interruptionEnded` does nothing if the owner had paused before or during the interruption.
- `takePhoto`: the file name comes from `nextFile(.photo, ext: "heic", …)`; the place from `Place.stamp` when location is on; the photo is listed in `session.json` only after the camera has written the file. A failure adds `couldNotTakePhoto` and lists nothing.
- `setLocation(on: false)` writes the marker; from then on `Place.stamp` is called with `enabled: false`.
- `stop`: closes the span if one is open, finishes any open note, then `SessionStore.finalize`. If finalizing fails, `couldNotSave` and the session stays unfinished.
- After `stop`, `resume` starts a new span and the session is unfinished again until the next `stop` (spec 5.1: a stopped session can be reopened to resume recording). Its checksums are cleared when it becomes unfinished, so a stale checksum can never sit beside a changed file.
- `open` on a session that was cut off: `SessionStore.droppingMissingFiles`, then `recoverAfterCrash(spanDurationMs: audioLength(open span's file), at: now)`, save, and a `recovered` notice. The session is left paused.

`Fakes.swift` holds `FakeClock` (settable host seconds, wall, offset, zone), `FakeAudio` (records the URLs it was started with, writes a few bytes to each, returns a settable length, can be told to throw), `FakeCamera` (writes a few bytes; can be told to throw), `FakeLocation` (settable fix).

- [x] **Step 1: Failing tests**

```swift
func testStartingASessionRecordsAtOnce()                 // folder exists; one open span; audio started on audio/audio-001.m4a; first row "Recording started · local time, UTC+5:45"; isRecording
func testDefaultTitleIsTheLocalDateAndTime()             // "2026-11-23 10:42"
func testPauseAndResumeMakeTwoSpans()                    // FakeAudio length 9_950 for 10 s on the clock → span durations [9_950, …]; files audio-001, audio-002; markers Paused, Resumed
func testNotesAndPhotosWhilePausedAreNotOnAudio()        // rows made while paused have isOnAudio false
func testInterruptionClosesTheSpanAndResumeOpensANewOne() // interruptionBegan("phone call") → span endedBy interruption, marker "Interrupted (phone call) · …"; note typed during it is off audio; interruptionEnded → new span, marker Resumed
func testAnInterruptionDoesNotUndoAPause()               // pause, interruptionBegan, interruptionEnded → still paused
func testTakingAPhoto()                                  // file photos/photo-0001.heic exists; item listed with place when location on and the fix is fresh; FakeCamera received the same place and moment
func testNoPlaceAfterLocationIsSwitchedOff()             // setLocation(on: false), fresh fix present, takePhoto → item gps nil, camera got place nil; marker "Location off" on the page
func testAPhotoThatFailsIsNotListed()                    // FakeCamera throws → no photo item, notice couldNotTakePhoto
func testStartLocationArrivesLate()                      // start with no fix; fix arrives; locationFixArrived → manifest.startLocation set once; a later fix does not move it
func testStaleOrInvalidFixesAreNotStamped()              // Place.stamp: fix 61 s old → nil; horizontalAccuracyM -1 → nil; verticalAccuracyM -1 → alt nil; enabled false → nil
func testStopFinishesTheSession()                        // every listed file has a checksum; SessionCheck.folder(folder).findings == []; isRecording false
func testResumingAfterStopClearsChecksums()              // stop, resume → sha256 all nil, one more span; stop again → finished again, SessionCheck clean
func testEverythingIsSavedAsItHappens()                  // after each of: typing, finishNote, takePhoto, pause — SessionStore.load(folder) == controller.manifest
func testASaveThatFailsIsReportedAndRetried()            // make the folder read-only (or remove it) → notice couldNotSave; put it back; next change saves and load == manifest
func testRenamingTheSession()                            // setTitle("Market visit") → folder renamed to "2026-11-23 1042 Market visit [….]", session.json inside says the same, recording continues into the same audio file
func testParticipants()                                  // setParticipants("P-014, P-015  P-016") → ["P-014","P-015","P-016"]
func testTheCounter()                                    // 10 s recorded and paused, then 5 s into a new span → 14_950 or so: closed spans' durations plus the clock since the open one began
func testNoMicrophone()                                  // FakeAudio throws on start → session exists, not recording, no span, notice couldNotRecord; resume later works
```

- [x] **Step 2: Run; expect `cannot find 'SessionController' in scope`.**
- [x] **Step 3: Implement** `Hardware.swift`, then the controller.
- [x] **Step 4: All tests pass.**
- [x] **Step 5: Commit.** `feat(core): the session controller`

---

**As built (2026-11-24), where it differs from the text above:**

- There is no `PhotoCapturing` protocol and no `takePhoto()`. The screen takes a photo in two steps: `preparePhoto() -> PhotoRequest` at the shutter (file name, where to write, the moment, the place), then `photoSaved(_:)` or `photoFailed(_:reason:)` when the camera has finished. A real camera answers later, not at once.
- A photo reported after a pause is placed on the span that was recording when the shutter was pressed.
- An untitled session keeps an empty title in `session.json`; `Manifest.displayTitle` gives `2026-11-23 10:42` wherever a title is shown.
- `setTitle` renames the folder only once nothing is being recorded into it.
- Typing is saved at most every two seconds; `saveIfNeeded()` saves what is pending.
- The start location is only taken from a reading within two minutes of the start.
- A photo taken after stop makes the session unfinished until the next stop.
- `SessionTimeline` gained `addMarker`, `setChecksums`, `clearChecksums`, `openSpanElapsedMs(at:)`; `SessionStore` gained `checksums(for:in:)`.

### Task 5: Coming back after the app was killed

**Files:**
- Modify: `Core/Sources/ScrivnerCore/SessionController.swift`
- Test: `Core/Tests/ScrivnerCoreTests/SessionRecoveryTests.swift`

**Interfaces:**
- Consumes: `SessionController.open` (Task 4), `SessionStore.droppingMissingFiles`, `SessionTimeline.recoverAfterCrash`.

- [x] **Step 1: Failing tests**

```swift
func testReopeningAfterTheAppWasKilled()
// Start; type a note at 20 s and finish it; take a photo at 30 s; start typing a second note at 44 s (not finished).
// Throw the controller away without stopping (the app was killed). FakeAudio's file is on disk.
// open(folder, audioLength: { _ in 42_000 }) →
//   notices == [.recovered(dropped: [])]; not recording; span 0 closed as crash-recovered with durationMs 42_000;
//   the note typed at 44 s is still on the page, placed at 42_000; last row "Interrupted (the app was closed unexpectedly) · local time, UTC+5:45";
//   resume() → a second span on audio/audio-002.m4a; stop() → SessionCheck.folder(folder).findings == [].
func testReopeningWhenThePhotoNeverReachedTheDisk()
// As above, but the photo's file is deleted before reopening → recovered(dropped: ["photos/photo-0001.heic"]), no photo row.
func testReopeningWhenTheAudioCannotBeRead()
// audioLength returns nil → the span is as long as the last thing placed on it; still finishes cleanly.
func testOpeningAFinishedSessionChangesNothing()
// stop, then open → no notices; session.json byte-for-byte as it was; not recording.
func testOpeningAFolderThatIsNotASession()
// open on an empty folder throws.
```

- [x] **Step 2: Run; see them fail for the reason each names.**
- [x] **Step 3: Implement what is missing in `open`.**
- [x] **Step 4: All tests pass.**
- [x] **Step 5: Commit.** `feat(core): reopening a session that was cut off`

---

### Task 6: The session list, the export record and the warnings

**Files:**
- Create: `Core/Sources/ScrivnerCore/SessionSummary.swift`, `Core/Sources/ScrivnerCore/ExportRecord.swift`, `Core/Sources/ScrivnerCore/Warnings.swift`
- Test: `Core/Tests/ScrivnerCoreTests/SessionListTests.swift`, `Core/Tests/ScrivnerCoreTests/WarningsTests.swift`

**Interfaces:**
- Produces:

```swift
public struct SessionSummary: Equatable, Sendable, Identifiable {
    public let id: String
    public let folder: SessionFolder
    public let title: String
    public let startedAt: Instant
    public let utcOffset: UTCOffset
    public let recordedMilliseconds: Int
    public let photoCount: Int
    public let clipCount: Int
    public let isFinished: Bool
    public let export: ExportState
    /// Newest first. A folder whose session.json cannot be read is listed in `unreadable`, never dropped silently.
    public static func list(in root: URL, exports: ExportRecord) -> (sessions: [SessionSummary], unreadable: [String])
}

public enum ExportState: Equatable, Sendable { case never, exported(Instant), changedSince(Instant) }

/// When each session was last shared, kept in one file beside the sessions folder, not inside any session.
public struct ExportRecord: Equatable, Sendable {
    public init()
    public static func load(from url: URL) -> ExportRecord            // a missing or damaged file is an empty record
    public func save(to url: URL) throws
    public mutating func noteExport(of manifest: Manifest, sessionJSON: Data, at instant: Instant)
    public func state(for manifest: Manifest, sessionJSON: Data) -> ExportState   // compares the SHA-256 of session.json
    public mutating func forget(sessionId: String)
}

extension SessionStore {
    /// Removes a session's folder and everything in it. The only way the app deletes recordings (spec 5.1).
    public static func delete(_ folder: SessionFolder) throws
}

public enum InstallWarning: Equatable, Sendable {
    case daysLeft(Int), endsToday, expired, unknown
    /// From the expiry date written inside the app's own install profile.
    public static func state(expires: Instant?, now: Instant) -> InstallWarning
    public var isUrgent: Bool { get }                                  // two days or fewer left, today, or expired
    public var text: String { get }                                    // "This install stops working in 5 days", "… tomorrow", "… today", "This install has stopped working. Reinstall it from the Mac.", ""
    /// Finds the expiry date in the raw bytes of an `embedded.mobileprovision` file.
    public static func expiry(inProfile data: Data) -> Instant?
}

public enum ReadinessWarning: Equatable, Sendable {
    case lowStorage(freeBytes: Int64), lowBattery(percent: Int)
    /// Before a session starts: under 2 GB free; under 20 % battery and not charging.
    public static func check(freeBytes: Int64?, batteryLevel: Double?, isCharging: Bool) -> [ReadinessWarning]
    public var text: String { get }     // "Only 1.2 GB of storage is free. A long session with video may not fit.", "The battery is at 15 % and the phone is not charging."
}
```

- [x] **Step 1: Failing tests**

```swift
// SessionListTests
func testListIsNewestFirstWithCounts()          // two finished sessions an hour apart and one still recording → order, recordedMilliseconds, photoCount, clipCount, isFinished
func testAnUnreadableFolderIsReportedNotDropped() // a folder with a broken session.json → in `unreadable` by folder name
func testExportStates()                         // never → noteExport → .exported(t); change the session (add a note, save) → .changedSince(t); export again → .exported(t2)
func testExportRecordSurvivesSavingAndLoading() // save, load → equal; load from a missing file → empty; load from a file of rubbish → empty
func testDeletingASession()                     // SessionStore.delete → the folder is gone and the list no longer has it; ExportRecord.forget drops its entry; deleting a folder that is not a session (no session.json) throws and removes nothing
// WarningsTests
func testInstallWarningStates()                 // 5 days 3 h left → .daysLeft(5), text "This install stops working in 5 days", not urgent; 1 day 2 h → .daysLeft(1), "… tomorrow", urgent; 3 h → .endsToday, urgent; past → .expired; nil → .unknown, text ""
func testExpiryIsFoundInsideAProfile()          // bytes holding binary junk, then "<key>ExpirationDate</key>\n\t<date>2026-12-01T10:15:00Z</date>", then junk → 2026-12-01T10:15:00.000Z; no key → nil
func testReadinessWarnings()                    // 1.2 GB free → lowStorage with the text above; 0.15 not charging → lowBattery; 0.15 charging → none; nil readings → none
```

- [x] **Step 2: Run; expect build failures naming the new types.**
- [x] **Step 3: Implement.** `ExportRecord` is stored as JSON written with `JSONValue`.
- [x] **Step 4: All tests pass on Linux; push and confirm they pass on the hosted Mac too.**
- [x] **Step 5: Commit.** `feat(core): session list, export record and warnings`

---

## Execution record (2026-11-24)

All six tasks are done on branch `stage-1a`. A fresh reviewer then read the whole branch and found one must-fix and seven should-fix items; all were fixed in one pass, each with a test that failed first. After the fixes: 209 tests pass on Linux, and the same tests pass on a Mac hosted by GitHub.

What the review changed, beyond the "As built" note under Task 4:

- A listed file that has gone is taken off the page, with a notice, when a session is stopped or opened. One missing file can no longer leave a session that cannot be finished.
- A reopened session keeps the location state its page last recorded; the app's setting can only turn it off. A session started with location off says "Location off" on its page.
- Photo numbers never go down and are never reused; names already on disk are skipped for photos and audio.
- A photo that arrives after Stop keeps the session finished.
- `RecorderState` (recording, paused, interrupted with a reason, stopped). After an interruption the controller keeps trying to record until the owner pauses or stops; `interruptionEnded()` can be called any number of times.
- The "app was closed unexpectedly" line carries the time of the cut-off.
- `AudioRecording.start(writingTo:)` returns the moment the audio really began, and the span starts there.
- New notices: `filesMissing`, `filesNotListed`. Notices carry plain words, never raw error text. `hasUnsavedChanges`.

## What this leaves for stage 1c (the real microphone, camera and location)

From the review. The first group is certain; the second needs settling on the device.

Certain:

- Every `preparePhoto()` must be answered with exactly one `photoSaved` or `photoFailed`, and the controller must outlive photos in flight.
- The camera must write to a temporary name the workbench would not pick up, and move the file into place when it is complete.
- When `AudioRecording.stop()` returns, the audio file must be final: closed, with its tags written. The folder may be renamed and the file read through straight afterwards.
- `Moment.host` must be on the same clock as audio timestamps (`mach_absolute_time`). It stops while the device sleeps, which is harmless, because the device does not sleep while a span is open.
- iOS does not say why an interruption happened and does not always say when it ended. The adapter gives a general reason, and calls `interruptionEnded()` when the app comes to the front and on a timer while interrupted.
- Stop recording before storage is completely full, so the file can be finished and `session.json` saved.
- Backup exclusion and file protection go on the sessions folder, not on files: each save replaces the file.
- `AudioRecording.start` should return the first sample's moment.

To settle on the device:

- Whether iOS will write Apple's creation-date, make and model keys into an `.m4a`, and whether the creation time it sets itself falls within a second of the span's start. The checker compares both.
- Whether a place set through AVFoundation's common key lands where the checker expects. The checker now finds a place wherever it lands.
- Whether iOS puts a Live Photo identifier on ordinary photos.
- Reading the length of an audio file that was cut off may only be possible asynchronously; `audioLength` is synchronous.
- The location adapter must keep delivering readings while standing still, or photos after a quiet stretch get no place under the 60-second freshness rule. Freshness uses the wall clock.
- Reading every file through at Stop on the main thread will take seconds once there is video.
