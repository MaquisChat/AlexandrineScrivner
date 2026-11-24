# Alexandrine Scrivner (iOS field notebook recorder): Design Spec

- **Date:** 2026-11-23
- **Status:** Draft for review
- **Scope of this document:** the iPhone and iPad recorder app and the session folder it produces. The workbench side (importing a session folder and showing photos and notes beside the transcript) is a separate project in the workbench's own repository, designed after this one; section 9 says what it will need from this one.
- **Working name:** "Alexandrine Scrivner", after this repository. The owner has not named the app. "Scrivener" on its own is an existing writing app that the workbench integrates with, so the full name is used to avoid confusion.
- **The workbench:** the owner's research workbench, which they call "amanuensis". It is the repository `MaquisChat/AlexandrineOxiana`. Everything said about it here was checked against its code at commit `0ad6506` (2026-11-11).
- **Mockups:** https://claude.ai/artifact/DXmmJ1nTQupQFifG6zKfhT (private to the owner). Five screens: layout A, layout B, video while writing, hidden, and the iPad mini.

Throughout, **"owner decision"** marks something the owner said in the design conversation. **"Proposed"** marks a call made on the owner's behalf that they have not explicitly confirmed. Anything unmarked in sections 5 to 8 is proposed.

---

## 1. Purpose

The owner is a social science researcher who takes field notes and conducts interviews. They want one app on their phone or tablet that works like a notebook with a recorder running underneath: audio records continuously while they type or handwrite notes, take photos, and shoot video clips. Everything is stamped with the time it was made, and photos and clips with the place.

The reason for the stamps is what happens afterwards. The session is imported into the workbench, which transcribes the audio. Each photo, clip and note then appears beside the transcript text that was being spoken when it was made.

**Success looks like:** the owner runs an hour-long interview with the device on the table, types notes throughout, takes a dozen photos and two video clips, hides the screen twice, locks the phone once, and afterwards has one session folder in which every item can be placed on the audio to within a second, and which the workbench imports without complaint.

## 2. Goals, non-goals, anti-goals

### Goals

1. Continuous audio recording for a whole session, including while the app is in the background or the device is locked.
2. Typed notes (on-screen keyboard or an attached Apple keyboard) and, on iPad, handwriting and sketches with a stylus, on the same page as the recording. The owner's stylus is a third-party one, not an Apple Pencil (section 3).
3. Photos and video clips taken from inside the notebook, including a photo while a clip is recording.
4. Every item (note, ink, photo, clip) time-stamped and placed on the audio timeline. Photos and video clips are also geo-stamped (owner decision). Notes and ink carry no location of their own.
5. A hide button that instantly blanks the screen while recording continues, built so other cover screens can be added later.
6. Two page layouts the owner can switch between at any time.
7. Export of a self-contained session folder that the workbench can import, today and after its importer is extended.

### Non-goals (this project)

- Transcription on the device. The workbench does it.
- The workbench importer and the transcript-with-photos view (next project, in the workbench's repository).
- Cloud sync, upload, accounts, or any network use at all.
- App Store distribution. The app is installed from the owner's Mac.
- Handwriting converted to text.
- Covers other than the blank screen.
- Trimming or editing media; a continuous GPS track; an app passcode or Face ID lock; Apple Watch; Android.
- Taking a photo with the iPhone's hardware buttons (volume or Camera Control), including while the screen is covered. A natural later addition, not part of this project.

### Anti-goals (these make it a failure even if it "works")

- **A recording the owner believes is running but is not.** Any stop that the owner did not ask for must be visible on the page and, where the system allows, announced.
- **Lost audio.** A crash, a dead battery or a phone call must not cost more than a few seconds of what was already recorded.
- **Times that cannot be trusted.** Positions on the audio must not depend on the wall clock staying still.
- **Sensitive material leaving the device unasked.** Nothing goes to Photos, iCloud, or any server.
- **Pretending to hide from the operating system.** iOS shows its own recording indicator; the app must not claim or attempt otherwise.
- **A session folder the workbench cannot read.** Compatibility is checked, not assumed (section 6.4).

## 3. Constraints

**Platform rules (iOS and iPadOS):**

- The camera stops when the app leaves the foreground or the device locks. Audio may continue in the background. So video and photos are foreground-only; audio is the continuous record.
- The system's recording indicator (the green or orange dot, and the indicator at the top of the screen while the app records in the background) cannot be hidden or altered by any app.
- An app cannot send itself to the background. Only the user can, by going home or switching apps.
- Handwriting with a stylus is an iPad feature. The iPhone gets typing only.

**The owner's setup:**

- A Mac, and a **free** Apple developer account (owner decision: "not paid"). Consequences: no TestFlight; an installed app stops launching seven days after it was installed and must be re-installed from the Mac; data on the device survives a re-install.
- **Devices (owner, 2026-11-24):** an iPhone 17 Pro, an iPad mini (6th generation), and a third-party stylus that is not an Apple Pencil. What follows from that:
  - **Minimum OS.** The iPhone 17 Pro shipped with iOS 26, and the iPad mini 6 can run iPadOS 26 and 27. Proposed minimum: iOS and iPadOS 26, which means the iPad must be on 26 or later.
  - **Small iPad screen.** The iPad mini is 744 by 1133 points. The iPad layout is designed for that size first.
  - **The stylus may count as a finger.** Whether iPadOS treats this stylus as a pencil or as an ordinary touch is unknown until it is tried on the device. So ink must work with any touch (stylus or finger), and must not depend on pressure, tilt, hover, squeeze, double-tap, or handwriting-to-text. If the stylus is treated as a finger, the system offers no palm rejection, and writing with a resting hand will be unreliable; the remedy would be an Apple Pencil the mini 6 supports (2nd generation or USB-C). Stage 0 finds out which case applies.
- **The Mac** is still unknown: Apple silicon or Intel, its macOS version, and whether Xcode is installed (section 11). This decides whether the approach works at all. The newest Xcode (27) runs only on Apple silicon Macs with macOS Tahoe 26.6 or later, and a device on iOS or iPadOS 27 needs it. It must be settled before stage 0.

**How the work gets done:**

- The owner has limited coding experience and directs the work. So: conventional technology, Architecture Decision Records in `docs/adr/`, and tests that report in plain language, as in the workbench.
- Code is written by agents in cloud sessions that cannot compile or run iOS apps. Building happens on the owner's Mac. Camera, microphone, background and lock behaviour can only be checked on a real device, by the owner.
- **Feedback loop (proposed; needs the owner's agreement, section 11).** The owner connects the Mac to the agent's session through Claude's Remote Control, so the agent can run builds, the simulator and the tests on the Mac, and read the Mac's and devices' versions itself. If the Mac is not connected, the fallback is one script on the Mac that builds, runs the tests and saves a log for the owner to send back. Either way, as much logic as possible lives in the core (section 7) so it can be tested without a device, and the adapters around Apple's frameworks stay thin.
- Swift is not installed in the cloud environment today, and this repository has no automated checks yet. Installing Swift there and adding a Linux check for the core's tests are setup tasks at the start of stage 1. The core's tests must run on the Mac regardless.

## 4. Approaches considered

1. **A native Apple app** (Swift, using Apple's capture, location and Pencil frameworks directly). Background recording, a photo during video, and Pencil ink are what these frameworks are built for. Cost: a second language next to the workbench's TypeScript and Python, and all builds and device checks happen on the owner's Mac and devices.
2. **A shared-code app** (React Native, TypeScript). Would share the session format code with the workbench. But background audio, camera and Pencil still need native pieces underneath, with an extra layer in between, adding risk exactly where the app must not fail.
3. **No new app yet.** Record with Voice Memos, photograph with Camera, and teach the workbench to line files up by clock time. Cheapest, but gives no notebook, no hide button and no timed notes.
4. **A web app** (the workbench spec's Phase 5 plan for phones). Ruled out: iOS stops a web page recording once it leaves the screen.

**Chosen: 1, the native Apple app, in its own repository** (owner decisions). One idea is kept from 3 for the workbench side: line things up by clock time, so a photo from any camera can also be placed in a transcript.

## 5. What the app does

### 5.1 Sessions

- The home screen is a list of sessions, newest first: title, date, length, counts of photos and clips, and whether it has been exported.
- **New session** opens an empty page and starts recording audio at once.
- A session has a title (defaults to its date and start time, editable) and an optional free-text line for participant codes (for example `P-014`), matching the workbench's pseudonymous participant codes.
- **Pause** stops audio capture; **resume** continues. Notes, photos and clips still work while paused. Pause means the microphone is off: a clip made while paused has no sound, and the page says so.
- **Stop** ends the session. A stopped session can be reopened to read it, add notes, or resume recording.
- Sessions are deleted only by the owner, one at a time, with a confirmation.

### 5.2 The page

The page is a single column of **blocks** in the order they were made:

| Block | Made by | Its time is |
|---|---|---|
| Text | typing; a new paragraph starts a new block | when its first character was typed |
| Ink (iPad) | writing or drawing with a stylus or a finger | when its first stroke began; every stroke also keeps its own time |
| Photo | the Photo button | the moment of capture |
| Video clip | the Video button, then Stop clip | when the clip started; its length is kept |
| Marker | the app | recording started, paused, resumed, stopped, or interrupted, with the reason; location switched off or on |

Editing an older text block later does not move it; the block keeps its original time and also records when it was last changed.

### 5.3 Times (owner decision, with one reading to confirm)

- Times shown on the page are **clock time in the device's local time zone**, for example `10:43`, following the device's 12 or 24 hour setting. Seconds are stored but not shown.
- The page **notes when recording is happening**: a marker line when recording starts, pauses, resumes and stops, giving the clock time and the time zone (for example "Recording started · local time, UTC+0"). *This is a reading of the owner's words "with notes of what time they are recording" and should be confirmed.*
- The recorder's own counter (length recorded so far) stays visible in the recorder bar or pill.

Section 6 says what is stored behind each displayed time.

### 5.4 Two layouts with a switch (owner decision)

The same page can be shown two ways. A button in the header switches between them at any time, including mid-recording, and the app remembers the last choice.

- **A, "Times in the margin":** a full recorder bar at the top (recording state, counter, level meter, pause), the clock time of every block down the left margin, and a bottom bar with labelled Photo and Video buttons and a large Hide button.
- **B, "Plain page":** reads like ordinary notes. The recorder is a small pill showing the counter; there is no margin; photos and clips sit as thumbnails beside the text with their time underneath; three round buttons (photo, video, hide) float at the bottom.

On iPad the capture buttons run down the left edge and the drawing tools sit at the bottom; both layouts otherwise apply. A tool in that set switches between writing by hand and typing, so drawing never depends on the app telling a stylus from a finger.

### 5.5 Capture

- **Photo:** one tap takes a photo with the rear camera and adds it to the page. No separate camera screen is required for the common case; a camera view with flip and zoom is available on a long press. Photos work while a clip is recording.
- **Video:** one tap starts a clip; the button becomes Stop clip. A small live camera tile floats over the page and can be dragged out of the way; typing and writing continue underneath.
- The session's audio keeps recording throughout. A clip also carries its own sound so it plays on its own, except a clip made while paused (5.1), which is silent.
- If the app leaves the foreground or the device locks during a clip, the clip ends cleanly and a marker says why. The clip is **not** restarted automatically on return.
- Taking a photo or starting or stopping a clip must not interrupt or audibly glitch the session audio.

### 5.6 Hide (owner decision: blank screen now, provision for others)

- The Hide button, or a keyboard shortcut when a keyboard is attached, covers the whole screen in black at once. The status bar and home indicator are hidden as far as the system allows.
- Everything keeps recording, including a video clip in progress.
- A **double-tap** anywhere, or the same keyboard shortcut, brings the page back. Single touches and typing do nothing while covered.
- While covered with a clip recording, the screen is kept awake (otherwise auto-lock would end the clip). While covered with audio only, the device may auto-lock as normal; audio continues.
- When the app goes to the background, the picture iOS keeps for the app switcher is the blank cover, not the page.
- **Provision for other covers:** the cover is a replaceable part. Each cover supplies what is drawn and what gesture dismisses it. This project ships one, the blank cover; adding another later must not require changes to recording or the page.

### 5.7 Location

- With location on, the app records where the device is at session start and at each photo and clip. Photos and clips also carry the location inside the file. Notes and ink are not located.
- Whether location is on for a new session comes from a setting in the app, which is on when the app is first installed. For sensitive work the owner turns the setting off **before** starting the session, so nothing is located at all. The header shows the state throughout.
- The switch in the header can be flipped during a session. Turning it off stops every further location stamp from that moment and writes a marker on the page. It does **not** remove locations already saved, and the app says so when the switch is flipped. The app never rewrites files to strip location.
- The app asks for location permission "while using the app" only.
- The device records exact coordinates. Coarsening or stripping is the workbench's job at import, under each project's location rule (keep, coarsen to city level, or strip).

### 5.8 Storage and safety

- Session files live inside the app's own storage. Nothing is written to the Photos library.
- Session media is excluded from iCloud and computer backups by default. *This trades recoverability for privacy; the owner should confirm.* The exported badge on each session, and the install warning below, are there to prompt exporting promptly.
- The app makes no network connections and contains no analytics.
- **Install warning:** because of the seven-day limit, the app shows how many days its install has left, on the home screen, and warns prominently in the last two days.
- If recording stops for a reason the owner did not choose (a phone call, another app taking the microphone, storage full, an error), the app resumes when it can, writes a marker on the page, and posts a notification if it could not resume.
- Before starting a session the app checks free storage and battery and warns if either is low.

### 5.9 Export

- Sessions are visible as plain folders in the Files app and, over a cable, in Finder. **A folder is what the workbench imports today**, so this is the main route.
- **Share** on a session produces one zip of the session folder and hands it to the system share sheet, so it can go by AirDrop or be saved to Files. On the Mac the zip is opened into a folder before importing.
- A session shows when it was last exported, and whether it has changed since.

## 6. The session folder

This is the contract between the recorder and the workbench. **It is defined in this repository**; the workbench reads it. It must be readable by a person and by a program, in keeping with the workbench's "portable folder of human-readable files".

### 6.1 Layout

```
2026-11-23 1042 Market visit [k3f9]/
  session.json          the manifest and timeline
  notes.md              the typed notes as plain text with their times, for people
  audio/
    audio-001.m4a       one file per unbroken stretch of recording
    audio-002.m4a
  photos/
    photo-0001.heic
  video/
    clip-0001.mov
  ink/                  (iPad stage)
    ink-0001.png        the ink as a picture
    ink-0001.drawing    the ink as Apple's drawing data (PencilKit)
```

**Rules:**

- Folder name: `<date> <start time> <title> [<4-character id>]`, cleaned the way the workbench cleans its own folder names: Unicode NFC; the characters `< > : " / \ | ? *` and control characters become `-`; runs of spaces collapse; no trailing dots or spaces; Windows reserved names (CON, PRN, AUX, NUL, COM1-9, LPT1-9) get a `_` prefix; the whole name is at most 150 UTF-8 bytes, shortened on a whole character with `…`.
- No file or folder name begins with a dot. The workbench skips those.
- File names inside the folder are plain and readable, because the workbench uses them in the titles it gives imported items.
- All paths in `session.json` are relative to the session folder and use forward slashes.
- Ids are UUIDv7. Instants are UTC, ISO 8601, with milliseconds and `Z` (for example `2026-11-23T10:42:10.120Z`). Hashes are SHA-256, 64 lower-case hex characters. These match the workbench's own conventions.
- Every media file is listed with its hash, so an importer can verify it.

### 6.2 `session.json`, in outline

```json
{
  "format": "ao-field-session",
  "version": 1,
  "id": "…",
  "title": "Market visit",
  "participants": ["P-014"],
  "researcher": "display name, if set",
  "device": { "model": "…", "os": "…", "app": "…" },
  "startLocation": { "lat": 0, "lon": 0, "alt": 0, "accuracyM": 0 },
  "spans": [
    {
      "id": "…",
      "file": "audio/audio-001.m4a",
      "sha256": "…",
      "startedAt": "2026-11-23T10:42:10.120Z",
      "utcOffset": "+00:00",
      "timeZone": "Europe/Lisbon",
      "durationMs": 551000,
      "endedBy": "pause"
    }
  ],
  "items": [
    { "id": "…", "kind": "marker", "type": "recording-started", "at": "…", "utcOffset": "+00:00" },
    { "id": "…", "kind": "text", "at": "…", "utcOffset": "+00:00", "spanId": "…", "offsetMs": 65000,
      "text": "P-014 has run the stall since 2009.", "modifiedAt": "…" },
    { "id": "…", "kind": "photo", "at": "…", "utcOffset": "+00:00", "spanId": "…", "offsetMs": 185000,
      "file": "photos/photo-0001.heic", "sha256": "…",
      "gps": { "lat": 0, "lon": 0, "alt": 0, "accuracyM": 0 } },
    { "id": "…", "kind": "video", "at": "…", "utcOffset": "+00:00", "spanId": "…", "offsetMs": 430000,
      "durationMs": 48000, "endedBy": "user", "sound": true,
      "file": "video/clip-0001.mov", "sha256": "…", "gps": {} },
    { "id": "…", "kind": "ink", "at": "…", "endAt": "…", "utcOffset": "+00:00", "spanId": "…", "offsetMs": 300000,
      "file": "ink/ink-0001.png", "data": "ink/ink-0001.drawing",
      "strokes": [ { "at": "…", "offsetMs": 300000, "bounds": [0, 0, 0, 0] } ] }
  ]
}
```

**What each time means:**

- `at` is the instant the item was made. `utcOffset` is the device's offset from UTC at that instant, so local clock time can always be shown again, even after travel.
- `spanId` and `offsetMs` say where the item falls on the audio: which recording span, and how far into that span's file. They are absent when nothing was recording (paused, or after stop).
- **`offsetMs` is measured against the audio's own clock, not worked out by subtracting wall-clock times.** If the device clock is corrected or the time zone changes mid-session, positions on the audio stay right.
- A **span** is one unbroken stretch of recorded audio. Pausing, an interruption, or recovery after a crash ends one span and the next begins a new file. `endedBy` says which.
- `startLocation` and each item's `gps` are present only if location was on at that moment. Markers of type `location-off` and `location-on` record when the switch changed, so a reader can tell "no location because it was off" from "no location because none was available".
- A video item made while paused has `"sound": false`.

**One definition of the format.** The format is written down once, as a JSON Schema file in this repository, with at least one complete example session folder kept as a test fixture. The recorder's tests check that what it writes matches the schema. The workbench's importer project will take a pinned copy of the schema and fixture and test against them.

### 6.3 What each media file must carry inside itself

The workbench reads times and places from the files, not from `session.json`. So every media file must describe itself, with the same metadata an iPhone's own Camera writes:

| File | Must carry | What the workbench does with it |
|---|---|---|
| Photo (`.heic`) | EXIF original date and time with sub-seconds; EXIF offset time original; make, model and lens; GPS latitude, longitude and altitude with their references, when location is on | capture time, time zone, device and lens on the imported item; location, governed by the project's rule |
| Clip (`.mov`) | QuickTime creation time (UTC); Apple's creation-date key with the local offset; Apple's make and model keys; Apple's ISO 6709 location key, when location is on | the same |
| Audio (`.m4a`) | QuickTime creation time (UTC); Apple's creation-date key with the local offset; make and model | capture time and time zone; audio is never located |

No file carries Apple's Live Photo content identifier, which would make the workbench pair files as Live Photos.

### 6.4 Compatibility with the workbench as it is today

Checked by reading the workbench's import code (`packages/library/src/import/device.ts`, `packages/library/src/extract/exif.ts`, the device-import route, the bulk import scanner, the media worker, and its naming and id rules).

**What works now, before the workbench knows anything about `session.json`:**

- Its device import takes a folder, walks its subfolders, and picks up files by extension. `.heic`, `.mov` and `.m4a` are all recognized. `session.json`, `notes.md` and `.drawing` files are ignored rather than rejected.
- Each photo, clip and audio file becomes its own item (field photo, field video, field recording), titled from its capture date, device model and file name.
- All items from one import can be linked to one fieldwork session and its participants, chosen in the workbench at import.
- Capture time is read from the tags in 6.3, in the order original, creation, then modified; a time taken from "modified" is treated as unverified, so the recorder always writes the first two.
- Location is read from inside photos and clips, and the project's rule (keep, coarsen, strip) is applied to viewing copies; originals are never changed.
- HEIC photos get viewing copies, and `.m4a` audio can be transcribed.

**Known gaps until the workbench's importer is extended (section 9):**

- **Zip.** Device import takes a folder, not a zip. A shared zip is opened on the Mac first.
- **Notes.** Typed notes are not imported. They stay in `notes.md` and `session.json`.
- **Placement.** Nothing yet places photos, clips or notes beside the transcript. Each audio span is a separate recording with its own transcript.
- **Ink pictures.** `.png` is a photo type to the workbench, so ink pictures will arrive as field photos. Acceptable for now; the importer will treat them as ink.

**How compatibility is kept, not assumed:**

- A **session checker** in this repository reads a session folder and verifies it: `session.json` matches the schema, every listed file exists with the right hash, and every media file exposes the tags in 6.3 with values that agree with `session.json` (same instant to within a second, same offset, same location). It reads tags the way the workbench does (the workbench uses ExifTool).
- Each stage's device checklist ends by importing a real session folder into the workbench with its device import and comparing what arrives with the page.

## 7. How it is built

Decided by the owner: **a native Apple app, in this repository** (`MaquisChat/AlexandrineScrivner`), separate from the workbench. The rest of this section is proposed and left to the builder to refine.

- **Repository layout:** the Xcode app project; a Swift package for the core; `format/` for the JSON Schema and the example session folder; `tools/` for the session checker and the Mac build script; `docs/adr/` and `docs/superpowers/` for decisions, specs and plans.
- **Two layers.**
  - **Core:** sessions, blocks, the timeline, span bookkeeping, the manifest writer, folder naming, export. Plain Swift with no Apple-only frameworks, so its tests run with `swift test` on a Mac and on Linux.
  - **App:** the screens, and thin adapters around Apple's audio, camera, location and Pencil frameworks. The core talks to these through small interfaces so it can be tested with fakes.
- **One owner of the microphone.** The session audio and the sound in a video clip come from the same microphone at the same time. The design must have a single component own the microphone and feed both, rather than two recorders competing. How (which Apple audio and capture APIs, in what arrangement) is for the builder to settle in the spike below.
- **Crash-safe audio.** Audio must be written so that a crash or power loss keeps everything up to the last few seconds. On next launch the app finds an unfinished session, repairs it, closes the span as `crash-recovered`, and tells the owner.
- **Files written while locked.** Recording continues with the device locked, so session files need a protection level that allows writing while locked.
- **Formats:** audio AAC in `.m4a`, mono, speech-appropriate quality; photos HEIC; video HEVC or H.264 in `.mov`, 1080p. All are formats the workbench already accepts (6.4).
- **Decision records:** an ADR for the audio pipeline (after the spike), one for the session folder format, and one for the cover mechanism.

### Stages

Each stage ends with something the owner can use.

0. **Spike (throwaway).** A bare test app, installed on the owner's iPhone, that proves the risky part: session audio keeps recording, without gaps, while a video clip starts and stops, a photo is taken, the app goes to the background, the device locks, and a phone call comes in. Its findings decide the audio pipeline and are written into an ADR. On the iPad, the same spike reports whether the owner's stylus arrives as a pencil or as a finger, and whether a resting palm is ignored. Its code is not kept.
1. **iPhone core.** Sessions, continuous audio (background, lock, interruptions, crash recovery), typed notes, photos, both layouts with the switch, the hide button with the blank cover, location, the session folder with its schema and checker, export, the install warning, and the keyboard shortcut for hide.
2. **Video clips.** Clips with the floating camera tile, a photo during a clip, and clip-ending rules.
3. **iPad and stylus.** The iPad layout at iPad mini size, ink blocks with per-stroke times, and ink in the session folder.

The workbench project (section 9) can start once stage 1 produces real session folders.

### Testing

- **Core:** unit tests for the timeline and span bookkeeping (including pause, interruption, crash recovery, a clock change mid-session, and a time zone change mid-session), the manifest against the JSON Schema, folder naming, and export.
- **Session checker:** run against the example session folder in tests, and against real session folders from the device.
- **Device checklist:** a short written script the owner runs on the real device at the end of each stage (start a session, lock the phone for five minutes, take a call, shoot a clip while typing, hide and return, export, run the checker, and import the folder into the workbench). Results are recorded in plain language.
- Whatever can be automated on the Mac's simulator is; the checklist covers what cannot.

## 8. Left to the builder

- The app's exact minimum iOS and iPadOS version. 26 is proposed (section 3); the builder may raise it to 27 if both devices are on 27 and it simplifies the work.
- The audio pipeline, subject to the spike and the requirements in sections 5.5 and 7.
- The keyboard shortcut for hide, avoiding system shortcuts.
- How ink blocks begin and grow on the iPad page, and the drawing tool set, within the stylus constraint in section 3.
- Exact audio and video quality settings, and whether the shutter sound can be suppressed where the system permits.
- What the session checker is written in, provided it runs on the Mac and on Linux.
- Visual detail beyond the mockups, which show layout and intent rather than final styling. Colours and typeface follow the workbench's theme (its `packages/ui/src/theme/tokens.css`; interface typeface Goudy Old Style with Sorts Mill Goudy as the free fallback).
- Dark appearance, Dynamic Type and VoiceOver support follow normal platform practice.

## 9. What the workbench project will need (not designed here)

- An importer that reads a session folder or its zip: one fieldwork session, with the audio, photos, clips, notes and ink as linked items, verified against the hashes in `session.json`.
- A transcript view that places photos, clips, notes and ink beside the transcript segment being spoken at their time, using each item's span and offset, and falling back to clock time for media that did not come from the recorder.
- Stitching a session's audio spans into one timeline.
- Mapping the participant codes typed in the recorder to the project's participants and their consent records.
- The project's governance applied at import as for any device import, including the location rule.

## 10. Decisions and proposals at a glance

| Topic | Choice | Whose |
|---|---|---|
| What it is | A notebook with a recorder underneath; audio, video, photos and notes in one interface | Owner |
| Devices | iPhone 17 Pro and iPad mini (6th generation); Apple keyboard, on-screen keyboard, a third-party stylus | Owner |
| Minimum OS | iOS and iPadOS 26 | Proposed |
| Ink input | Any touch, stylus or finger; nothing that needs a genuine Apple Pencil | Proposed, from the owner's stylus |
| Approach | Native Apple app | Owner |
| Where it lives | Its own repository, `MaquisChat/AlexandrineScrivner` | Owner |
| Workbench compatibility | Checked against the workbench's code; kept by a session checker and an import step in each device checklist | Owner asked for the check; the mechanism is proposed |
| Background | Audio continues in the background and when locked; video cannot | Platform rule, accepted by owner |
| Hide | Blank screen now, built to take other covers later | Owner |
| Layouts | Both A and B, switchable | Owner |
| Page times | Local clock time, with notes of when recording is happening | Owner; the reading of "notes" is to confirm |
| Location | Photos and video clips are geo-stamped | Owner |
| Developer account | Free | Owner |
| Location detail | Also stamped at session start; notes and ink not located; default from an app setting (on at install); switching off mid-session stops further stamps but keeps earlier ones; exact on device | Proposed |
| Pause | Microphone off; clips made while paused are silent | Proposed |
| Returning from hide | Double-tap, or the keyboard shortcut; typing ignored while covered | Proposed |
| Clip on background or lock | Ends cleanly with a marker; not restarted | Proposed |
| Storage | Inside the app only; not Photos; excluded from iCloud and computer backups | Proposed; backup exclusion to confirm |
| Transfer | Plain folders in Files and Finder; zip through the share sheet | Proposed |
| Install warning | Days left shown in the app | Proposed |
| Order of work | Spike, iPhone core, video, iPad and stylus; workbench side after stage 1 | Proposed |
| Building and testing | Mac connected to the agent's session for builds and tests; log script as fallback | Proposed; needs the owner's agreement |
| No network | The app never connects to anything | Proposed |

## 11. Open questions for the owner

Asked on 2026-11-23; answers go here and into the sections they affect.

1. **The Mac.** Apple silicon or Intel, its macOS version, and whether Xcode is installed and which version. Also whether the iPhone and iPad are on version 26 or 27. Together these confirm the Mac can install onto the devices at all. (The device models were answered on 2026-11-24; see section 3.)
2. **Connecting the Mac.** Whether the owner will connect the Mac to the agent's session so builds and tests can be run directly (section 3). If yes, the Mac's versions in question 1 can be read rather than asked.

Flagged earlier and cheap to change later, so not blocking: the reading of "notes of what time they are recording" (5.3), and excluding session media from backups (5.8).
