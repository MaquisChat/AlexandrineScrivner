# Stage 1b: The iPhone App's Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The iPhone app as the owner will see it, running in the simulator with stand-in hardware: the session list, the page in both layouts with the switch, typing notes, taking photos, pause and stop, the blank cover, and the warnings; built, walked through and photographed on a hosted Mac on every push.

**Architecture:** A SwiftUI app in `App/`, generated with XcodeGen like the stage 0 test app. Screens hold no session logic: a `SessionModel` wraps `SessionController` from `ScrivnerCore` and republishes its `Page`. The microphone, camera and location chip are behind the protocols from stage 1a; this stage supplies stand-ins that write real, small files (a silent recording, a generated picture), so the whole app runs where there is no microphone or camera. Stage 1c swaps in the real ones.

**Tech Stack:** Swift, SwiftUI, XcodeGen 2.46.0, XCUITest. Built with whatever Xcode the hosted Mac has (26.3 on 2026-11-24) for the iPhone 17 Pro simulator on iOS 26; the owner's Mac builds the same project with Xcode 27.

**Spec:** `docs/superpowers/specs/2026-11-23-field-notebook-recorder-design.md`, sections 5.1 to 5.9. The approved mockups are the visual reference: layout A "Times in the margin", layout B "Plain page", and the hidden screen.

## What this plan leaves to stage 1c

Real audio (waiting on the stage 0 device results), the real camera, real location, recording in the background and with the phone locked, file protection, notifications, and everything that needs the owner's devices.

## Global Constraints

- Minimum iOS 26.0. iPhone only in this stage (`TARGETED_DEVICE_FAMILY` 1); the iPad layout is stage 3.
- No network use, no analytics, no third-party packages (spec 5.8).
- Session folders live in the app's Documents folder under `Sessions/`, visible in the Files app (spec 5.9). Nothing is written to the Photos library.
- Every word shown comes from `Wording`, `Page`, `InstallWarning`, `ReadinessWarning` or `SessionNotice` in `ScrivnerCore` where one exists, so screens and `notes.md` say the same thing.
- Colours and type follow the mockups: ink `#1C1B19`, secondary `#5F5B52`, rule `#E2DFD7`, recording red `#9A2B1F`, accent teal `#1F5E63`, paper `#FFFFFF`, strip `#FBFAF7`, pill `#F1EFE9`. Notes are set in a serif face (the system's serif design), controls in the system face. Touch targets are at least 44 points.
- Every control has an accessibility label, and the ones the walkthrough uses have an accessibility identifier.
- The repository is public: no names, emails, team ids or device identifiers. `App/Local.xcconfig` (the signing team) is never committed.
- Work on branch `stage-1b`, cut from `stage-1a`.

## How this stage is tested

SwiftUI cannot be compiled on Linux, so the loop is: push, and read what the hosted Mac says. The "Mac checks" workflow builds the app for the simulator, runs a UI walkthrough that drives it like a person would and takes screenshots, pulls the session folder the app wrote out of the simulator, and runs `scrivner-check` on it. The screenshots and the session folder are kept as artifacts of the run.

Because each round takes several minutes, a UI test and the screen it drives are written together and the test is seen to pass on the Mac, not first seen to fail. Logic that can be tested on Linux still gets a failing test first.

## Review Focus

1. **The app is closed (swiped away) while recording, and opened again.** The session is listed, opens repaired, and says what happened. Walkthrough step `testComingBackAfterBeingClosed` (Task 4).
2. **Typing fast, then pressing return, then typing again.** Two notes with their own times; nothing typed is lost. `testWritingTwoNotes` (Task 3).
3. **Hide, while typing.** The cover shows nothing of the page, ignores single taps and typing, and returns on a double tap with the note intact. `testHideAndReturn` (Task 4).
4. **A very long session title, and none.** The header does not break; an untitled session shows its date and time. Screenshot `untitled-session` (Task 3).
5. **Large text sizes.** At the largest accessibility size the page still scrolls and no control is cut off. Screenshot `large-text` (Task 5).

---

### Task 1: What the screens need from Core

**Files:**
- Modify: `Core/Sources/ScrivnerCore/SessionController.swift`
- Test: `Core/Tests/ScrivnerCoreTests/SessionControllerTests.swift`

**Interfaces:**
- Produces: `preparePhoto(fileExtension: String = "heic") -> PhotoRequest`, so the stand-in camera can write a JPEG where the simulator cannot write HEIC; numbering is shared across endings. `var isFinished: Bool` (no span open and every file has its checksum). `var openNoteText: String?` (the text of the note being written, for the screen to show after coming back from the cover).

- [x] **Step 1: Failing tests** `testAPhotoCanBeAJPEG` (`preparePhoto(fileExtension: "jpg")` → `photos/photo-0001.jpg`, then the default → `photos/photo-0002.heic`), `testIsFinished` (false while recording, true after stop, false after resume), `testOpenNoteText`.
- [x] **Step 2: Run on Linux; see them fail to build.**
- [x] **Step 3: Implement.**
- [x] **Step 4: `swift test --package-path Core` passes.**
- [x] **Step 5: Commit.** `feat(core): what the screens need from the session controller`

---

### Task 2: The app's skeleton, built on the hosted Mac

**Files:**
- Create: `App/project.yml`, `App/Local.xcconfig.example`, `App/Sources/ScrivnerApp.swift`, `App/Sources/Theme.swift`, `App/Sources/AppModel.swift`, `App/Sources/SessionListView.swift`, `App/UITests/WalkthroughTests.swift`
- Modify: `tools/mac-bootstrap.sh` (also writes `App/Local.xcconfig`), `tools/mac-build.sh` (also generates and compiles the app, unsigned), `.github/workflows/mac.yml` (runs the walkthrough in the simulator and keeps its screenshots), `.gitignore`

**Interfaces:**
- Produces:
  - Target `Scrivner` (bundle id `$(BUNDLE_ID_PREFIX).scrivner`, display name "Scrivner"), depending on the local package `../Core`; target `ScrivnerUITests`.
  - `AppModel` (`@MainActor`, `ObservableObject`): `sessions: [SessionSummary]`, `unreadable: [String]`, `installWarning: InstallWarning`, `refresh()`, `sessionsRoot: URL`. With the launch argument `-uiTesting`, it uses a fresh, empty folder for sessions.
  - `SessionListView`: title "Sessions", a "New session" button (identifier `new-session`), one row per session (title, date and start time, length, photo count, "Not finished" or the export state), the install warning when there is one, and an empty state.
  - `tools/mac-walkthrough.sh`: builds for the simulator, runs the UI tests on "iPhone 17 Pro", exports the screenshots to `build/screenshots/`. Last line `WALKTHROUGH OK` or `WALKTHROUGH FAILED: <why>`.

- [x] **Step 1: Write the project, the skeleton and one UI test** `testTheListStartsEmpty`: launch with `-uiTesting`, expect the text "No sessions yet" and the `new-session` button, take the screenshot `empty-list`.
- [x] **Step 2: Push; read the hosted Mac's log; fix until the app builds and the test passes.**
- [x] **Step 3: Download the screenshot and look at it.**
- [x] **Step 4: Commit.** `feat(app): the app's skeleton and the session list`

---

### Task 3: A session on screen, in the margin layout

**Files:**
- Create: `App/Sources/SessionModel.swift`, `App/Sources/Hardware/SystemClock.swift`, `App/Sources/Hardware/StandInAudio.swift`, `App/Sources/Hardware/StandInCamera.swift`, `App/Sources/Hardware/StandInLocation.swift`, `App/Sources/SessionView.swift`, `App/Sources/MarginLayout.swift`, `App/Sources/PageRows.swift`
- Modify: `App/Sources/AppModel.swift`, `App/Sources/SessionListView.swift`, `App/UITests/WalkthroughTests.swift`

**Interfaces:**
- Produces:
  - `SystemClock: SessionClock` (monotonic seconds, the wall clock, the current time zone and its offset).
  - `StandInAudio: AudioRecording`: on stop, writes a silent AAC `.m4a` as long as the time since start, and returns that length.
  - `StandInCamera`: `capture(_ request: PhotoRequest) throws` draws a picture saying "Stand-in photo" and the time, and writes it as HEIC, or JPEG if HEIC cannot be written, with the EXIF time, sub-seconds and offset, make, model and lens, and GPS when the request has a place.
  - `StandInLocation: LocationProviding`: a fixed fix, refreshed on request (off unless `-uiTestingLocation` is given).
  - `SessionModel` (`@MainActor`, `ObservableObject`): wraps one `SessionController`; publishes `page`, `isRecording`, `counter` (text from `Wording.length`), `isLocationOn`, `notices`, `draft` (the note being typed); methods `pause`, `resume`, `stop`, `takePhoto`, `noteChanged`, `noteFinished`, `setLocation`, `setTitle`. A one-second timer refreshes the counter and calls `saveIfNeeded`.
  - `SessionView` with the margin layout: the recorder bar (red dot, "Recording" or "Paused", the counter, pause or resume; identifiers `recorder-state`, `counter`, `pause-resume`), the strip (title and participants, location state), the rows with their times in a 58-point margin, the note field at the foot of the page (identifier `note-field`; return finishes the note), and the bottom bar with Photo, Video (shown but disabled until stage 2) and Hide (identifiers `photo`, `hide`), and a Stop button behind a confirmation (identifier `stop`).

- [x] **Step 1: UI tests** `testStartingASession` (tap `new-session` → `recorder-state` reads "Recording", the first row reads "Recording started"), `testWritingTwoNotes` (type a line, return, type another, return → both on the page in order), `testTakingAPhoto`, `testPauseAndResume`, `testStopReturnsToTheListWithTheSessionFinished`, and screenshots `margin-layout`, `untitled-session`.
- [x] **Step 2: Implement; push; fix until green on the hosted Mac.**
- [x] **Step 3: Look at the screenshots against the mockup; fix what is off.**
- [x] **Step 4: Commit.** `feat(app): a session on screen, with stand-in hardware`

---

### Task 4: The plain layout, the switch, the cover, and coming back

**Files:**
- Create: `App/Sources/PlainLayout.swift`, `App/Sources/Cover.swift`
- Modify: `App/Sources/SessionView.swift`, `App/Sources/AppModel.swift`, `App/UITests/WalkthroughTests.swift`

**Interfaces:**
- Produces:
  - `PlainLayout`: the title in the serif face with "Since 10:42 · UTC+5:45", the recorder pill (dot and counter; tapping it pauses or resumes), notes with no margin, photos as 76-point thumbnails at the right with their time underneath, markers as a thin centred line of small text, and three round floating buttons (photo, video disabled, hide).
  - The layout switch in both headers (identifier `layout-switch`); the choice is remembered (`UserDefaults`, key `layout`).
  - `protocol Cover { associatedtype Body: View; var body: Body { get } }` with `BlankCover`; `CoverHost` shows the chosen cover over everything, hides the status bar and home indicator, ignores single taps and typing, and dismisses on a double tap or the keyboard shortcut ⌘⇧H (the same shortcut hides). While covered, the app's snapshot for the app switcher is the cover.
  - On launch, a session that was cut off is opened through `SessionController.open`, and its `recovered` notice is shown as a banner.

- [x] **Step 1: UI tests** `testSwitchingLayouts` (screenshot `plain-layout`), `testHideAndReturn` (screenshot `hidden`, which must be entirely black; single tap does nothing; double tap returns with the half-typed note still in the field), `testComingBackAfterBeingClosed` (start, type, terminate the app, relaunch → the session is in the list as "Not finished"; opening it shows "Interrupted (the app was closed unexpectedly)").
- [x] **Step 2: Implement; push; fix until green.**
- [x] **Step 3: Look at the screenshots.**
- [x] **Step 4: Commit.** `feat(app): the plain layout, the switch, the cover, and recovery on launch`

---

### Task 5: Warnings, settings, sharing and deleting

**Files:**
- Create: `App/Sources/SettingsView.swift`, `App/Sources/ShareSession.swift`
- Modify: `App/Sources/SessionListView.swift`, `App/Sources/AppModel.swift`, `App/UITests/WalkthroughTests.swift`

**Interfaces:**
- Produces:
  - The install warning on the list (from `embedded.mobileprovision` when the app has one; nothing in the simulator), prominent when urgent.
  - Readiness warnings shown before a session starts, with "Start anyway".
  - Settings: location on for new sessions (default on), clock style (follows the device unless overridden).
  - Share: a zip of the session folder through the system share sheet (`NSFileCoordinator` with `.forUploading`), recorded in `ExportRecord` (`exports.json` beside `Sessions/`); the list shows "Shared 24 Nov, 10:42" or "Changed since it was shared".
  - Delete: swipe on a row, then a confirmation naming the session.

- [x] **Step 1: UI tests** `testDeletingASessionAsksFirst`, `testSettingsTurnLocationOffForNewSessions`, screenshots `list-with-sessions`, `large-text` (launch with the largest accessibility text size).
- [x] **Step 2: Implement; push; fix until green.**
- [x] **Step 3: Commit.** `feat(app): warnings, settings, sharing and deleting`

---

### Task 6: The checker reads what the app wrote

**Files:**
- Modify: `tools/mac-walkthrough.sh`, `.github/workflows/mac.yml`, `README.md`, `docs/guides/mac-setup.md`

- [x] **Step 1:** After the walkthrough, `tools/mac-walkthrough.sh` copies the app's `Sessions/` folder out of the simulator (`xcrun simctl get_app_container`) to `build/walkthrough-sessions/` and runs `scrivner-check` on it. It must end `SESSION CHECK OK` for the finished sessions. With `--media` the report is printed but does not fail the run: the stand-in recorder does not write the tags a real recording will, and that is stage 1c's to close.
- [x] **Step 2:** The workflow keeps `build/screenshots/` and `build/walkthrough-sessions/` as artifacts.
- [x] **Step 3:** Docs: what the stage 1b app is and is not, and how the owner installs it (`tools/mac-install.sh` gains the app as a second target).
- [x] **Step 4: Commit and push; confirm on the hosted Mac.** `ci: the checker reads the session folders the app wrote in the simulator`

---

## Execution record (2026-11-24)

All six tasks are done on branch `stage-1b`. The app is built for the iPhone simulator on a GitHub-hosted Mac on every push, walked through by `App/UITests/WalkthroughTests.swift`, photographed, and the session folders it writes are given to `scrivner-check`.

As built, where it differs from the tasks above:

- **Four long walks, not twelve separate tests.** Each launch takes about a minute on the hosted Mac. `test1ListSettingsAndDeleting`, `test2ComingBackAfterBeingClosed`, `test3AWholeSession`, `test4LargestTextInTheDark`. Every tap waits for its target and the walk carries on if it never comes, so one failure does not hide the rest.
- **Screenshots are read from the run's log.** This session cannot fetch GitHub's stored files, so `tools/mac-walkthrough.sh` prints small copies as text when `SCRIVNER_PRINT_SCREENSHOTS=1`.
- **No clock-style setting.** The app follows the phone's own 12-hour or 24-hour setting.
- **The note field is a wrapped `UITextView`** (`App/Sources/NoteField.swift`), not a SwiftUI `TextField`: Return has to end a note exactly once and leave the keyboard up.

A fresh reviewer then read the whole branch and returned "with fixes": one must-fix, thirteen should-fix and a list of smaller points. All of the first two groups were fixed, and most of the third. What the review changed:

- A red line on every screen says this is a trial version that records no sound (`Trial`, `TrialBanner` in `Theme.swift`). Stage 1c removes it with the stand-ins.
- Return ends a note directly; a repeated note is kept; pasted paragraphs become a note each.
- Tapping a note opens it for changing or deleting (`NoteEditor`). Tapping the title opens the title and participant codes (`SessionDetails`).
- The keyboard is up when a new session opens, comes back after the cover, and follows a change of layout (`WritingFocus`).
- A session cut off when the app was closed is repaired when the app opens and made complete as it stands (`AppModel.repairSessionsThatWereCutOff`; in Core, `SessionController.open` finishes a recovered session). The list says what was done.
- Opening a session only to read it never changes it: the "Location off" line owed by a setting that was turned off is written when something is next added (Core, three new tests).
- Location is confirmed in both directions, and shown in both layouts.
- The plain layout: controls on their own line above the title; the title scrolls with the page; the pill says what it is doing in words when not recording; the round buttons take their own room at the bottom; Stop is a button (the "more" menu it first sat in is gone, since the simulator could not press its items and everything else in it was already one tap away), with Close in its place for a finished session.
- The note field sits outside the lazily built rows. The walkthrough, not the review, found that on a page longer than the screen a new row could push the field out of view, where it was rebuilt and lost the keyboard.
- Sessions are left out of backups. The walkthrough's reset switch and its dark-appearance switch are compiled for the simulator only.
- Every notice is shown until dismissed. Stop stays on the session if it could not be finished. Pending changes are saved when the app leaves the front.
- Dark appearance; text size up to the largest setting (notes grow all the way, controls and titles to one and a half times).
- The keyboard shortcut is Command-Shift-B. VoiceOver's double tap dismisses the cover. `docs/adr/0004-the-cover.md` records the cover.
- Zips made for sharing are removed afterwards and at launch.
- The walkthrough's weak checks were rewritten: the hidden screen is compared pixel by pixel; markers are matched as markers; a photo is taken with location off; the title is changed; the layout is checked to be remembered between launches; stopping is done from the plain layout. Checks that read back what was just typed wait for it, because the hosted Mac is at times several times slower.

After the fixes, on the hosted Mac (run 45493319325, commit ea54199): the build script passes, 215 Core tests pass, all four walks pass, and `scrivner-check` accepts the session folder the third walk leaves behind (`SESSION CHECK OK`, 1 session, 0 problems, 0 warnings). The check of what is inside the media files reports the stand-in recordings, as expected: no creation date or device name, and a time taken when the file was written, not when the recording began. The two photos pass it, with a place in the first and none in the second.

The fix pass took six full rounds on the hosted Mac, about half an hour each. Two of the faults it met were in the app and were not in the review: the note field was lost on a long page, and the cursor opened at the start of a note being changed. The rest were the walkthrough's own: a button listed twice, a menu the simulator could not press, and checks that read the page before a slow machine had caught up.

Every decision made without asking, and what was left for later, is in `docs/judgment-calls-2026-11-24.md` under "The iPhone app's screens".

## What this adds to stage 1c's list

- Remove `Trial` and `TrialBanner` together with the stand-ins, and only then.
- The real recorder must keep counting while the app is in the background or the phone is locked; the stand-in does not.
- Check on a real phone: what the app switcher shows, whether the home indicator hides under the cover, and locking while covered.
- Sharing has no automatic check; walk through it by hand.
- Make the zip off the main thread once sessions have real audio in them.
