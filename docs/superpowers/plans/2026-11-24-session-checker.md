# Session Checker and a Real Worked Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A command-line checker that verifies a session folder the way spec 6.4 requires, a worked example with real media that passes it, and a recorded run of the workbench's own reader over that example.

**Architecture:** The checking rules are pure code in `ScrivnerCore`: they take a folder, a manifest and the facts read from media files, and return a list of findings. A thin executable, `scrivner-check`, in the same package reads the files, runs ExifTool as a child process and prints the report. The worked example's media become small real files, generated once by a script and committed. The workbench check is a script that runs the workbench's own scanning code from a local checkout.

**Tech Stack:** Swift 6 (Foundation only); ExifTool 13.59, the build the workbench uses (npm package `exiftool-vendored.pl` 13.59.3, run with the system's Perl); ffmpeg and Python with `pillow-heif`, only for generating the example's media; Node 22 with the workbench's own `tsx`, only for the workbench check.

**Spec:** `docs/superpowers/specs/2026-11-23-field-notebook-recorder-design.md`, sections 6.3 and 6.4.

## Global Constraints

- `ScrivnerCore` stays Foundation only, with no package dependencies, in Swift language mode 6. It must still build for iOS, so nothing in `ScrivnerCore` starts a child process; that lives in the executable target.
- Agreement between a media file and `session.json` (spec 6.4, verbatim): "same instant to within a second, same offset, same location". In numbers: instants at most 1000 ms apart; offsets exactly equal; latitude and longitude at most 0.0001 degrees apart; altitude at most 1 m apart when both sides give one.
- What each media file must carry is the table in spec 6.3. No file may carry Apple's Live Photo content identifier.
- ExifTool is the pinned build: `https://registry.npmjs.org/exiftool-vendored.pl/-/exiftool-vendored.pl-13.59.3.tgz`, SHA-256 `dea9f92a8748a75a43ff42aae017644a48982aead848f985c6a443ec11e0b8f5`.
- Everything the checker prints is a plain sentence that a person who does not program can act on. The last line of every script is a verdict in capitals: `SESSION CHECK OK (...)` or `SESSION CHECK FAILED (...)`.
- The repository is public. Generated media hold test patterns and tones only. No names, emails, team ids, device names or identifiers anywhere.
- Work on branch `checker`, cut from `foundations`.

## Review Focus

Inputs the spec implies that are most likely to bite, each pinned by a test in the task named:

1. **A folder that has been through Finder or AirDrop** gains `.DS_Store` and `._name` files. These are ignored (the Mac itself hides the second kind from programs, as the first run on a Mac showed); any other unlisted file is a warning, never a problem, and the verdict stays OK. `testWhatTheMacLeavesBehindIsIgnored`, `testStrayFilesAreWarnings` (Task 4).
2. **A Mac whose own time zone is not UTC.** ExifTool then prints QuickTime times in the Mac's zone, with its offset. Instants must still compare correctly. `testQuickTimeDatesInAnotherSystemZone` (Task 2).
3. **Location switched off, but a file carries a place anyway.** That is a privacy failure and must be a problem. `testLocationInsideAFileThatShouldHaveNone` (Task 3).
4. **A `session.json` that names a file outside the folder** (`../../x`). The checker reports it and never opens the file. `testPathsOutsideTheFolderAreNeverOpened` (Task 4).
5. **A session still recording, or cut off by a crash.** One clear finding, not a list of missing checksums. `testUnfinishedSessionGetsOneFinding` (Task 4).
6. **Southern and western hemispheres, and below sea level.** Signs must come out right from EXIF's separate reference tags. `testHemispheresAndBelowSeaLevel` (Task 2).

---

### Task 1: Dates as ExifTool prints them

**Files:**
- Modify: `Core/Sources/ScrivnerCore/Instant.swift`
- Create: `Core/Sources/ScrivnerCore/ExifDate.swift`
- Test: `Core/Tests/ScrivnerCoreTests/ExifDateTests.swift`

**Interfaces:**
- Produces:
  - `Instant.init?(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int, millisecond: Int)`: the fields read as UTC; nil when any field is out of range for a real date.
  - `struct ExifDate: Equatable, Sendable { let local: Instant; let offset: UTCOffset?; let hasFraction: Bool; var instant: Instant? }`. `local` is the clock reading as if it were UTC. `instant` is `local` minus `offset`, nil when there is no offset.
  - `ExifDate.init?(_ text: String)`: accepts `YYYY:MM:DD HH:MM:SS`, optionally `.` and 1 to 6 digits, optionally `Z` or `+HH:MM` / `-HH:MM`. Fractions are cut to milliseconds. Nil for anything else, including the all-zero date.

- [ ] **Step 1: Write the failing tests**

```swift
func testPlainDate() {
    let d = ExifDate("2026:11:23 10:44:02")
    XCTAssertEqual(d?.local.iso, "2026-11-23T10:44:02.000Z")
    XCTAssertNil(d?.offset); XCTAssertNil(d?.instant); XCTAssertEqual(d?.hasFraction, false)
}
func testFractionAndOffset() {
    let d = ExifDate("2026:11:23 10:44:02.120+05:45")
    XCTAssertEqual(d?.local.iso, "2026-11-23T10:44:02.120Z")
    XCTAssertEqual(d?.offset?.string, "+05:45")
    XCTAssertEqual(d?.instant?.iso, "2026-11-23T04:59:02.120Z")
    XCTAssertEqual(d?.hasFraction, true)
}
func testZuluAndLongFraction() {
    XCTAssertEqual(ExifDate("2026:11:23 10:47:20.120000Z")?.instant?.iso, "2026-11-23T10:47:20.120Z")
    XCTAssertEqual(ExifDate("2026:11:23 10:47:20-09:30")?.instant?.iso, "2026-11-23T20:17:20.000Z")
}
func testRejects() {
    for bad in ["0000:00:00 00:00:00", "garbage", "2026:02:30 10:00:00", "2026:11:23", "2026:11:23 24:00:00", "2026:11:23 10:44:02+5"] {
        XCTAssertNil(ExifDate(bad), bad)
    }
}
func testInstantFromFields() {
    XCTAssertEqual(Instant(year: 2024, month: 2, day: 29, hour: 23, minute: 59, second: 59, millisecond: 999)?.iso, "2024-02-29T23:59:59.999Z")
    XCTAssertNil(Instant(year: 2026, month: 2, day: 29, hour: 0, minute: 0, second: 0, millisecond: 0))
    XCTAssertNil(Instant(year: 2026, month: 13, day: 1, hour: 0, minute: 0, second: 0, millisecond: 0))
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Core --filter ExifDateTests`
Expected: does not build, `cannot find 'ExifDate' in scope`.

- [ ] **Step 3: Implement.** The new `Instant` initializer goes in `Instant.swift` beside `init?(iso:)` and shares its range checks; `init?(iso:)` should call it.

- [ ] **Step 4: Run all tests.** `swift test --package-path Core`. Expected: 69 tests, 0 failures.

- [ ] **Step 5: Commit.** `feat(core): dates as ExifTool prints them`

---

### Task 2: What a media file says about itself

**Files:**
- Create: `Core/Sources/ScrivnerCore/MediaFacts.swift`
- Test: `Core/Tests/ScrivnerCoreTests/MediaFactsTests.swift`

**Interfaces:**
- Consumes: `ExifDate` (Task 1), `JSONValue.parse`, `GeoPoint`.
- Produces:

```swift
public struct MediaFacts: Equatable, Sendable {
    public var original: ExifDate?        // photos: EXIF DateTimeOriginal, with sub-seconds and offset when present
    public var created: ExifDate?         // QuickTime CreateDate
    public var creationDate: ExifDate?    // Apple's creation-date key
    public var location: GeoPoint?        // accuracyM always nil
    public var make: String?
    public var model: String?
    public var lens: String?
    public var durationMs: Int?
    public var contentIdentifier: String?
    public var error: String?             // ExifTool could not read the file
    public init()
}
public enum ExifToolOutput {
    /// Everything before the file names on ExifTool's command line.
    public static let arguments: [String]
    /// Keyed by `SourceFile` exactly as ExifTool printed it.
    public static func parse(_ json: String) throws -> [String: MediaFacts]
}
```

`arguments` is exactly:

```
-json -n -G1 -api QuickTimeUTC=1
-ExifIFD:DateTimeOriginal -ExifIFD:OffsetTimeOriginal -Composite:SubSecDateTimeOriginal
-GPS:GPSLatitude -GPS:GPSLatitudeRef -GPS:GPSLongitude -GPS:GPSLongitudeRef -GPS:GPSAltitude -GPS:GPSAltitudeRef
-IFD0:Make -IFD0:Model -ExifIFD:LensModel
-QuickTime:CreateDate -QuickTime:Duration
-Keys:CreationDate -Keys:GPSCoordinates -Keys:Make -Keys:Model
-ContentIdentifier -ExifTool:Error
```

Reading rules:
- `original`: from `Composite:SubSecDateTimeOriginal` when present (it carries the fraction and the offset); otherwise from `ExifIFD:DateTimeOriginal`, with `ExifIFD:OffsetTimeOriginal` as its offset when that parses. The composite is used because ExifTool prints the bare sub-second tag as a number, which loses leading zeros.
- `created` from `QuickTime:CreateDate`; `creationDate` from `Keys:CreationDate`.
- `location`: from the EXIF tags, where latitude is negative when the reference is `S`, longitude negative when `W`, altitude negative when the reference is `1`; or from `Keys:GPSCoordinates`, which is `lat lon` or `lat lon alt` separated by spaces, already signed.
- `make`, `model`: `IFD0:` first, else `Keys:`. `lens` from `ExifIFD:LensModel`.
- `durationMs` from `QuickTime:Duration`, seconds as a number, rounded to the nearest millisecond.
- `contentIdentifier` from any key ending in `:ContentIdentifier`. `error` from `ExifTool:Error`.
- A value of the wrong type is treated as absent. Output that is not a JSON array of objects throws.

- [ ] **Step 1: Write the failing tests.** The fixture is real ExifTool output for three generated files, pasted as a string constant.

```swift
static let fixture = """
[{ "SourceFile": "audio/audio-001.m4a",
   "QuickTime:CreateDate": "2026:11:23 04:57:10+00:00", "QuickTime:Duration": 551.04,
   "Keys:CreationDate": "2026:11:23 10:42:10+05:45", "Keys:Make": "Apple", "Keys:Model": "iPhone 17 Pro" },
 { "SourceFile": "video/clip-0001.mov",
   "QuickTime:CreateDate": "2026:11:23 05:04:20+00:00", "QuickTime:Duration": 48,
   "Keys:CreationDate": "2026:11:23 10:49:20+05:45", "Keys:GPSCoordinates": "27.7046 85.3076 1300",
   "Keys:Make": "Apple", "Keys:Model": "iPhone 17 Pro" },
 { "SourceFile": "photos/photo-0001.heic",
   "ExifIFD:DateTimeOriginal": "2026:11:23 10:45:15", "ExifIFD:OffsetTimeOriginal": "+05:45",
   "Composite:SubSecDateTimeOriginal": "2026:11:23 10:45:15.120+05:45",
   "GPS:GPSLatitudeRef": "N", "GPS:GPSLatitude": 27.7046, "GPS:GPSLongitudeRef": "E", "GPS:GPSLongitude": 85.3076,
   "GPS:GPSAltitudeRef": 0, "GPS:GPSAltitude": 1300,
   "IFD0:Make": "Apple", "IFD0:Model": "iPhone 17 Pro", "ExifIFD:LensModel": "iPhone 17 Pro back camera 6.765mm f/1.78" }]
"""

func testReadsAudioClipAndPhoto() throws {
    let facts = try ExifToolOutput.parse(Self.fixture)
    let audio = try XCTUnwrap(facts["audio/audio-001.m4a"])
    XCTAssertEqual(audio.created?.instant?.iso, "2026-11-23T04:57:10.000Z")
    XCTAssertEqual(audio.creationDate?.instant?.iso, "2026-11-23T04:57:10.000Z")
    XCTAssertEqual(audio.creationDate?.offset?.string, "+05:45")
    XCTAssertEqual(audio.durationMs, 551_040)
    XCTAssertNil(audio.location)
    let clip = try XCTUnwrap(facts["video/clip-0001.mov"])
    XCTAssertEqual(clip.location, GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: nil))
    XCTAssertEqual(clip.durationMs, 48_000)
    let photo = try XCTUnwrap(facts["photos/photo-0001.heic"])
    XCTAssertEqual(photo.original?.instant?.iso, "2026-11-23T05:00:15.120Z")
    XCTAssertEqual(photo.original?.hasFraction, true)
    XCTAssertEqual(photo.location, GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: nil))
    XCTAssertEqual(photo.make, "Apple"); XCTAssertEqual(photo.model, "iPhone 17 Pro")
    XCTAssertEqual(photo.lens, "iPhone 17 Pro back camera 6.765mm f/1.78")
}
func testPhotoWithoutSubSecondsOrOffset() throws {
    let facts = try ExifToolOutput.parse(#"[{"SourceFile":"p.heic","ExifIFD:DateTimeOriginal":"2026:11:23 10:45:15"}]"#)
    XCTAssertEqual(facts["p.heic"]?.original?.local.iso, "2026-11-23T10:45:15.000Z")
    XCTAssertNil(facts["p.heic"]?.original?.offset)
    XCTAssertEqual(facts["p.heic"]?.original?.hasFraction, false)
}
func testQuickTimeDatesInAnotherSystemZone() throws {
    // The same audio file read on a machine set to UTC+1.
    let facts = try ExifToolOutput.parse(#"[{"SourceFile":"a.m4a","QuickTime:CreateDate":"2026:11:23 05:57:10+01:00"}]"#)
    XCTAssertEqual(facts["a.m4a"]?.created?.instant?.iso, "2026-11-23T04:57:10.000Z")
}
func testHemispheresAndBelowSeaLevel() throws {
    let facts = try ExifToolOutput.parse(#"[{"SourceFile":"p.heic","GPS:GPSLatitudeRef":"S","GPS:GPSLatitude":33.9,"GPS:GPSLongitudeRef":"W","GPS:GPSLongitude":70.6,"GPS:GPSAltitudeRef":1,"GPS:GPSAltitude":12.5},{"SourceFile":"c.mov","Keys:GPSCoordinates":"-33.9 -70.6"}]"#)
    XCTAssertEqual(facts["p.heic"]?.location, GeoPoint(lat: -33.9, lon: -70.6, alt: -12.5, accuracyM: nil))
    XCTAssertEqual(facts["c.mov"]?.location, GeoPoint(lat: -33.9, lon: -70.6, alt: nil, accuracyM: nil))
}
func testErrorsAndLivePhotoIdentifier() throws {
    let facts = try ExifToolOutput.parse(#"[{"SourceFile":"x.heic","ExifTool:Error":"File format error"},{"SourceFile":"y.mov","Keys:ContentIdentifier":"ABC-123"}]"#)
    XCTAssertEqual(facts["x.heic"]?.error, "File format error")
    XCTAssertEqual(facts["y.mov"]?.contentIdentifier, "ABC-123")
}
func testNotJSONThrows() {
    XCTAssertThrowsError(try ExifToolOutput.parse("exiftool: command not found"))
    XCTAssertThrowsError(try ExifToolOutput.parse(#"{"SourceFile":"a"}"#))
}
func testArgumentsAskForNumbersAndGroups() {
    XCTAssertEqual(Array(ExifToolOutput.arguments.prefix(5)), ["-json", "-n", "-G1", "-api", "QuickTimeUTC=1"])
    XCTAssertTrue(ExifToolOutput.arguments.contains("-Keys:CreationDate"))
}
```

- [ ] **Step 2: Run to see them fail.** `swift test --package-path Core --filter MediaFactsTests`. Expected: `cannot find 'ExifToolOutput' in scope`.
- [ ] **Step 3: Implement** in `MediaFacts.swift`.
- [ ] **Step 4: Run all tests.** Expected: 76 tests, 0 failures.
- [ ] **Step 5: Commit.** `feat(core): read what ExifTool says about a media file`

---

### Task 3: Does each media file agree with the manifest

**Files:**
- Create: `Core/Sources/ScrivnerCore/CheckFinding.swift`, `Core/Sources/ScrivnerCore/MediaCheck.swift`
- Test: `Core/Tests/ScrivnerCoreTests/MediaCheckTests.swift`

**Interfaces:**
- Consumes: `MediaFacts` (Task 2), `Manifest`, `LocalClock`.
- Produces:

```swift
public struct CheckFinding: Equatable, Sendable {
    public enum Severity: Sendable { case problem, warning }
    public let severity: Severity
    public let subject: String     // a path inside the folder, "session.json", or "folder"
    public let message: String
    public init(_ severity: Severity, _ subject: String, _ message: String)
}
public enum MediaCheck {
    /// `facts` is keyed by the path each file has in `session.json`.
    public static func findings(for manifest: Manifest, facts: [String: MediaFacts]) -> [CheckFinding]
}
```

Rules. The subject is always the file's path. Clock times in messages are local to the item (`HH:MM:SS`), using the manifest's offset.

For every span's audio file, every photo and every video clip:

| Condition | Severity | Message |
|---|---|---|
| no facts for the file, or `error` set | problem | `could not be read: <error, or "ExifTool returned nothing for it">` (and no further rules for this file) |
| `contentIdentifier` present | problem | `carries a Live Photo identifier, which would make the workbench pair it with another file` |
| neither make nor model | warning | `does not name the device that made it (make and model)` |

Photos, against the item's `at`, `utcOffset` and `gps`:

| Condition | Severity | Message |
|---|---|---|
| `original` nil | problem | `has no capture time inside it (EXIF DateTimeOriginal)` |
| `original.offset` nil | problem | `has no time zone offset inside it (EXIF OffsetTimeOriginal)` |
| instant more than 1000 ms from `at` | problem | `says it was taken at <t1> but session.json says <t2>` |
| offset differs | problem | `says its offset from UTC is <o1> but session.json says <o2>` |
| `hasFraction` false | warning | `capture time has no sub-seconds` |
| `lens` nil | warning | `does not name the lens` |

Clips, against the item's `at`, `utcOffset`, `gps`, `durationMs`; and audio, against the span's `startedAt`, `utcOffset`, `durationMs`:

| Condition | Severity | Message |
|---|---|---|
| `created` nil or has no instant | problem | `has no creation time inside it (QuickTime CreateDate)` |
| `created.instant` more than 1000 ms off | problem | `says it was made at <t1> but session.json says <t2>` |
| `creationDate` nil or has no offset | problem | `has no creation date with the local offset inside it (Apple creation date)` |
| `creationDate.instant` more than 1000 ms off | problem | `says it was made at <t1> (Apple creation date) but session.json says <t2>` |
| `creationDate.offset` differs | problem | `says its offset from UTC is <o1> but session.json says <o2>` |
| both durations known and more than 1000 ms apart | warning | `is <d1> long but session.json says <d2>` |

Location, for photos and clips:

| Condition | Severity | Message |
|---|---|---|
| manifest has `gps`, file has none | problem | `has no location inside it although session.json gives one` |
| both, latitude or longitude more than 0.0001 apart, or both altitudes known and more than 1 m apart | problem | `says it was made at <lat>, <lon> but session.json says <lat>, <lon>` |
| manifest has no `gps`, file has a location | problem | `carries a location although session.json has none for it` |

Audio only:

| Condition | Severity | Message |
|---|---|---|
| file has a location | problem | `carries a location; audio is never located` |
| the file's duration is known and an item placed on this span has `offsetMs` more than 1000 ms past it | problem | subject the audio file: `is <d> long, but an item in session.json sits at <offset> on it` (once per span, for the furthest item) |

Durations and offsets in messages are `M:SS`. Ink files are not checked here; spec 6.3 asks nothing of them.

- [ ] **Step 1: Write the failing tests.** A helper builds a small finished manifest with `SessionTimeline` (one span of 60 s at offset `+05:45`; a photo with a location at 10 s; a clip with no location from 20 s to 30 s) and a matching `[String: MediaFacts]`. Tests:

```swift
func testAgreeingFilesGiveNoFindings()              // []
func testUnreadableFile()                           // facts[photo].error = "File format error" → exactly 1 problem, message hasPrefix "could not be read"
func testMissingFacts()                             // facts removed for the clip → 1 problem "could not be read: ExifTool returned nothing for it"
func testPhotoTimeOffByTwoSeconds()                 // 1 problem containing "says it was taken at 10:42:22 but session.json says 10:42:20"
func testPhotoTimeOffByNineHundredMillisecondsIsFine()   // []
func testPhotoWithoutOffset()                       // 1 problem containing "EXIF OffsetTimeOriginal"
func testPhotoWithWrongOffset()                     // same instant, offset +05:30 → 1 problem containing "offset from UTC is +05:30 but session.json says +05:45"
func testPhotoWithoutSubSecondsOrLens()             // 2 warnings, 0 problems
func testClipWithoutAppleCreationDate()             // 1 problem containing "Apple creation date"
func testClipDurationDiffers()                      // 1 warning "is 0:08 long but session.json says 0:10"
func testLocationMissingFromFile()                  // 1 problem "has no location inside it although session.json gives one"
func testLocationDiffers()                          // lat + 0.001 → 1 problem; lat + 0.00005 → []
func testLocationInsideAFileThatShouldHaveNone()    // clip facts get a location → 1 problem "carries a location although session.json has none for it"
func testAudioWithLocation()                        // 1 problem "carries a location; audio is never located"
func testAudioShorterThanAnItemsPosition()          // audio durationMs 15_000, clip sits at 0:20 → 1 problem "is 0:15 long, but an item in session.json sits at 0:20 on it", plus the duration warning
func testLivePhotoIdentifier()                      // 1 problem
func testNoMakeOrModel()                            // 1 warning
```

Each asserts the exact count of problems and warnings and the subject path.

- [ ] **Step 2: Run to see them fail.** Expected: `cannot find 'MediaCheck' in scope`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Expected: 93 tests, 0 failures.
- [ ] **Step 5: Commit.** `feat(core): check media files against the manifest`

---

### Task 4: Does the folder agree with its manifest

**Files:**
- Create: `Core/Sources/ScrivnerCore/SessionCheck.swift`
- Test: `Core/Tests/ScrivnerCoreTests/SessionCheckTests.swift`

**Interfaces:**
- Consumes: `CheckFinding` (Task 3), `SessionFolder`, `SessionStore.listedFiles(in:)`, `SessionStore.folderName(for:)`, `ManifestCoding.decode`, `Manifest.problems(finished:)`, `Manifest.isTidyRelativePath`, `SHA256Hex.ofFile`, `NotesMarkdown.render`.
- Produces: `public enum SessionCheck { public static func folder(_ folder: SessionFolder) -> (manifest: Manifest?, findings: [CheckFinding]) }`

Rules, in this order:

1. `session.json` is missing or not text → problem, subject `session.json`, `is missing` / `is not readable text`. Stop; manifest nil.
2. It does not decode → problem, subject `session.json`, `<path>: <message>` from `ManifestDecodeError` (or `is not valid JSON: <reason>`). Stop; manifest nil.
3. A span is open, or a listed file has no checksum → problem, subject `session.json`, `the session was not finished: it was still recording, was cut off, or its files have no checksums yet. Open it in the app so it can be finished.` The session then counts as unfinished. (A problem, not a warning: only a finished session should be imported, so the verdict must not be OK.)
4. Every `manifest.problems(finished:)` (finished unless rule 3 fired) → problem, subject `session.json`, `<path> <message>`.
5. Every listed file whose path is tidy: not there → problem `is listed in session.json but is not in the folder`; there but empty → problem `is empty`; a checksum is listed and differs → problem `does not match its checksum in session.json: the file has changed or is damaged`. A path that is not tidy is never opened (rule 4 has already reported it).
6. Every file found under the folder that is not listed, other than `session.json` and `notes.md` → warning, subject its path, `is in the folder but not listed in session.json`. Hidden files (name starting with a dot) included, except `.DS_Store` and `._name` files, which macOS leaves behind and which are ignored.
7. `notes.md` missing → warning `is missing`; present but different from `NotesMarkdown.render(manifest)` → warning `is out of date with session.json`.
8. The folder's name differs from `SessionStore.folderName(for:)` → warning, subject `folder`, `is named "<actual>"; its start time and title give "<expected>"`.

`listedFiles(in:)` and `isTidyRelativePath` are currently internal; both stay internal, since `SessionCheck` is in the same module.

- [ ] **Step 1: Write the failing tests.** Each starts from `ExampleSession.write(in:)` in a temporary folder, except where noted.

```swift
func testTheExampleIsClean()                        // manifest non-nil, findings == []
func testMissingSessionJSON()                       // 1 problem, subject "session.json", "is missing"; manifest nil
func testSessionJSONThatDoesNotDecode()             // replace `"version": 1` with `"version": 2` → 1 problem whose message hasPrefix "version"; manifest nil
func testSessionJSONThatIsNotJSON()                 // file "{" → 1 problem, message hasPrefix "is not valid JSON"
func testMissingMediaFile()                         // remove photos/photo-0001.heic → 1 problem, subject that path, "is listed in session.json but is not in the folder"
func testChangedMediaFile()                         // append one byte to audio/audio-001.m4a → 1 problem "does not match its checksum…"
func testEmptyMediaFile()                           // truncate video/clip-0001.mov → problems for "is empty" only (no second finding for the checksum)
func testStrayFilesAreWarnings()                    // add ".DS_Store", "photos/._photo-0001.heic", "extra.txt" → 3 warnings, 0 problems
func testNotesMissingOrStale()                      // remove notes.md → 1 warning; write "x" to it → 1 warning "is out of date with session.json"
func testRenamedFolder()                            // move the folder to "Renamed" → 1 warning, subject "folder"
func testUnfinishedSessionGetsOneFinding()          // SessionTimeline with startRecording and a photo, SessionStore.create, files written, no finalize → exactly the rule 3 problem and nothing else; the same after stop without finalize; clean after finalize
func testPathsOutsideTheFolderAreNeverOpened()      // edit session.json so a photo's file is "../outside.heic", and put a real file at that place → findings include the rule 4 problem for items[n].file and nothing with subject "../outside.heic"
```

- [ ] **Step 2: Run to see them fail.** Expected: `cannot find 'SessionCheck' in scope`.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run all tests.** Expected: 105 tests, 0 failures.
- [ ] **Step 5: Commit.** `feat(core): check a session folder against its manifest`

---

### Task 5: The report and the `scrivner-check` command

**Files:**
- Create: `Core/Sources/ScrivnerCore/CheckReport.swift`, `Core/Sources/scrivner-check/main.swift`
- Modify: `Core/Package.swift` (add the executable target)
- Test: `Core/Tests/ScrivnerCoreTests/CheckReportTests.swift`

**Interfaces:**
- Consumes: Tasks 2 to 4.
- Produces:

```swift
public enum CheckReport {
    /// The lines for one session folder.
    public static func render(folderName: String, findings: [CheckFinding], mediaChecked: Bool) -> String
    /// The last line of a run.
    public static func verdict(sessions: Int, problems: Int, warnings: Int) -> String
}
public struct CheckArguments: Equatable, Sendable {
    public var folders: [String]
    public var media: Bool
    public var exiftool: String?
    public static let usage: String
    /// Nil when the arguments make no sense (no folder, unknown flag, `--exiftool` with no value).
    public init?(_ arguments: [String])
}
```

Report text, exactly:

```
Session: 2026-11-23 1042 Market visit [1a2b]
  PROBLEM  photos/photo-0001.heic: says it was taken at 10:45:17 but session.json says 10:45:15
  warning  notes.md: is out of date with session.json
  Media tags were not checked. Run again with --media to check them.
```

- With no findings the body is one line: `  Nothing wrong.`
- The last line shown above appears only when `mediaChecked` is false.
- Problems come before warnings; within each, the order given.
- Verdict: `SESSION CHECK OK (1 session, 0 problems, 2 warnings)` when there are no problems, otherwise `SESSION CHECK FAILED (2 sessions, 3 problems, 1 warning)`. Singular and plural are both handled.

The command: `scrivner-check [--media] [--exiftool PATH] FOLDER...`

- A folder that has no `session.json` of its own but has subfolders that do is treated as a folder of sessions, and each is checked (`SessionStore.sessions(in:)`). A folder with neither is one session with a missing `session.json`.
- With `--media`, for each session whose manifest decoded: run ExifTool once with `ExifToolOutput.arguments` followed by the listed photo, clip and audio paths (tidy paths that exist only), with the session folder as the working directory, so `SourceFile` comes back as the manifest's own relative path. ExifTool is `--exiftool`, else the `EXIFTOOL` environment variable, else `exiftool` found on `PATH`.
- ExifTool cannot be started, or its output cannot be parsed → one problem, subject `folder`, `ExifTool could not be run: <reason>`.
- Exit status: 0 when there are no problems, 1 when there are, 2 with `CheckArguments.usage` on standard error when the arguments make no sense.
- `main.swift` holds only this wiring. It is exercised by Task 7's script, not by unit tests.

- [ ] **Step 1: Write the failing tests**

```swift
func testCleanReport()            // render(folderName: "S", findings: [], mediaChecked: true) == "Session: S\n  Nothing wrong.\n"
func testMixedReport()            // the exact block above (problem listed after the warning in the input, to prove ordering), mediaChecked: false
func testVerdicts()               // "SESSION CHECK OK (1 session, 0 problems, 2 warnings)"; "SESSION CHECK FAILED (2 sessions, 3 problems, 1 warning)"; "SESSION CHECK FAILED (1 session, 1 problem, 0 warnings)"
func testArguments()              // ["a"] → folders ["a"], media false; ["--media","--exiftool","/x/exiftool","a","b"] → all three set; [] → nil; ["--bogus","a"] → nil; ["a","--exiftool"] → nil
```

- [ ] **Step 2: Run to see them fail.**
- [ ] **Step 3: Implement** `CheckReport.swift`, then `main.swift`, then add to `Package.swift`: `.executableTarget(name: "scrivner-check", dependencies: ["ScrivnerCore"], swiftSettings: [.swiftLanguageMode(.v6)])` (match how the existing targets set the language mode).
- [ ] **Step 4: Run all tests, then the command by hand on the placeholder example.**

Run: `swift test --package-path Core` — expected 109 tests, 0 failures.
Run: `swift run --package-path Core scrivner-check format/examples/*` — expected `  Nothing wrong.` then the not-checked line, then `SESSION CHECK OK (1 session, 0 problems, 0 warnings)`, exit 0.
Run: `swift run --package-path Core scrivner-check` — expected the usage text, exit 2.

- [ ] **Step 5: Commit.** `feat: scrivner-check, the session folder checker`

---

### Task 6: A worked example with real media, somewhere that is not on UTC

**Files:**
- Create: `format/tools/make-example-media.py`, `tools/get-exiftool.sh`
- Modify: `Core/Sources/ScrivnerCore/ExampleSession.swift`, `Core/Tests/ScrivnerCoreTests/ExampleSessionTests.swift`, `format/examples/` (regenerated), `format/invalid/` (regenerated), `format/README.md`

**Interfaces:**
- Produces:
  - `ExampleSession.write(in root: URL, mediaFrom: URL? = nil) throws -> SessionFolder`: with `mediaFrom`, each listed file is copied from that folder (same relative path) when it exists there; otherwise the one-line placeholder is written, as now.
  - `tools/get-exiftool.sh`: downloads the pinned ExifTool (Global Constraints) into `.tools/exiftool/`, checks its SHA-256, and prints the path of the `exiftool` script on its last line. Does nothing but print the path when it is already there. Works on macOS (`shasum -a 256`) and Linux (`sha256sum`).
  - `format/tools/make-example-media.py SESSION_FOLDER EXIFTOOL`: writes real media for every span, photo and clip the folder's `session.json` lists.

The example moves to a clock that is not UTC, so that every local-time conversion in the format is exercised:

- start `2026-11-23T04:57:10.120Z`, offset `+05:45`, time zone `Asia/Kathmandu` (local clock 10:42, as before);
- place `GeoPoint(lat: 27.7046, lon: 85.3076, alt: 1300, accuracyM: 5)`;
- everything else in the script of the session is unchanged.

What `make-example-media.py` writes, from the manifest's own values:

| File | Made with | Carries |
|---|---|---|
| each span's `.m4a` | ffmpeg: a quiet 220 Hz tone, mono, 16 kHz, AAC at 12 kbit/s, exactly `durationMs` long | QuickTime create date = `startedAt` (UTC); Apple creation date = local time with the span's offset; Apple make `Apple`, model `iPhone 17 Pro` |
| each photo `.heic` | pillow-heif: a 320 by 240 flat colour | EXIF DateTimeOriginal, SubSecTimeOriginal and OffsetTimeOriginal from `at` and `utcOffset`; make, model, lens model `iPhone 17 Pro back camera 6.765mm f/1.78`; GPS latitude, longitude and altitude with references when the item has `gps` |
| each clip `.mov` | ffmpeg: a 160 by 120 test pattern at 5 frames a second, H.264, exactly `durationMs` long; a quiet tone as AAC sound when `sound` is true, no audio track when false | QuickTime create date; Apple creation date with offset; Apple make and model; Apple ISO 6709 location when the item has `gps` |

Tags are written with ExifTool (`-overwrite_original`), and ffmpeg is told not to add its own encoder tag where it can be avoided. The script ends by printing each file's size and the total.

Regenerating everything, in order: `UPDATE_EXAMPLE=1 swift test --package-path Core` (new times, placeholder media) → `python3 format/tools/make-example-media.py "format/examples/<folder>" "$(tools/get-exiftool.sh | tail -1)"` → `UPDATE_EXAMPLE=1 swift test --package-path Core` again (checksums of the real media) → `python3 format/tools/make-invalid.py .` → `(cd format && npm run validate)`.

- [ ] **Step 1: Change the golden test first.** In `ExampleSessionTests`: write with `mediaFrom:` the committed folder when it exists; add assertions `manifest.utcOffset.string == "+05:45"`, `manifest.createdAt.iso == "2026-11-23T04:57:10.120Z"`, the folder name still has the prefix `2026-11-23 1042 Market visit [`; and a new test:

```swift
func testCommittedExamplePassesTheFolderCheck() throws {
    let folders = SessionStore.sessions(in: Self.examples)
    XCTAssertEqual(folders.count, 1)
    let result = SessionCheck.folder(folders[0])
    XCTAssertEqual(result.findings, [])
    // Real media, not placeholders: every listed file is bigger than a one-line text file.
    for path in SessionStore.listedFiles(in: try XCTUnwrap(result.manifest)) {
        let size = try FileManager.default.attributesOfItem(atPath: folders[0].url(forRelativePath: path).path)[.size] as? Int
        XCTAssertGreaterThan(size ?? 0, 500, path)
    }
}
```

With `UPDATE_EXAMPLE=1` the test removes any other folder under `format/examples` before copying, so the old example does not linger.

- [ ] **Step 2: Run to see it fail.** Expected: does not build (`mediaFrom`), then after Step 3's signature exists, fails on the offset assertion.
- [ ] **Step 3: Implement** the `ExampleSession` change, `tools/get-exiftool.sh` and `make-example-media.py`.
- [ ] **Step 4: Regenerate** in the order above. Remove the old example folder from git.
- [ ] **Step 5: Verify.**

Run: `swift test --package-path Core` — expected 110 tests, 0 failures.
Run: `(cd format && npm run validate)` — expected `SCHEMA CHECK OK (3 valid, 15 rejected)`.
Run: `swift run --package-path Core scrivner-check --media --exiftool "$(tools/get-exiftool.sh | tail -1)" format/examples/*` — expected `  Nothing wrong.` and `SESSION CHECK OK (1 session, 0 problems, 0 warnings)`.
Check: the example folder is under 2 MB in total.

- [ ] **Step 6: Update `format/README.md`** (the example's media are now real, small and synthetic; how to regenerate; that the checker exists) and **commit.** `feat(format): a worked example with real media, on a clock that is not UTC`

---

### Task 7: Running the checker everywhere

**Files:**
- Create: `tools/check-example.sh`, `tools/mac-check-session.sh`
- Modify: `.github/workflows/core.yml`, `tools/mac-bootstrap.sh`, `tools/mac-build.sh`, `README.md`, `docs/guides/mac-setup.md`, `docs/adr/0003-session-folder-format.md` (one line under Consequences: the checker exists and the example's media are real)

**Interfaces:**
- Consumes: `scrivner-check` (Task 5), `tools/get-exiftool.sh` (Task 6).
- Produces:
  - `tools/check-example.sh`: proves the checker passes the example and catches a fault. Last line `EXAMPLE CHECK OK` or `EXAMPLE CHECK FAILED: <why>`.
  - `tools/mac-check-session.sh FOLDER`: for the owner, on a folder brought over from the phone. Runs the checker with `--media`, shows the report and saves it to `build/logs/`, scrubbed with `scrub` from `tools/mac-lib.sh`.

`tools/check-example.sh` does, in order:
1. `tools/get-exiftool.sh`, then builds the checker (`swift build --package-path Core --product scrivner-check`).
2. Runs it with `--media` on `format/examples`. Must exit 0 and print `SESSION CHECK OK`.
3. Copies the example to a temporary folder, moves one photo's EXIF time forward by one minute with ExifTool, runs the checker on the copy. Must exit 1, and the output must contain both `says it was taken at` and `does not match its checksum`.
4. Copies the example again, writes a location into the second clip (the one made with location off), runs the checker. Must exit 1 and contain `carries a location although session.json has none for it`.

- [ ] **Step 1: Write `tools/check-example.sh`** and run it. Expected last line: `EXAMPLE CHECK OK`.
- [ ] **Step 2: Prove it bites.** Temporarily change step 3's expected text to something that will not appear; run; expected `EXAMPLE CHECK FAILED`. Change it back; run; expected OK.
- [ ] **Step 3: Add the job to `.github/workflows/core.yml`:** job `session-check`, `runs-on: ubuntu-24.04`, `container: swift:6.4.3-noble`, installs `perl`, `curl` and `ca-certificates` with apt, checks out, runs `tools/check-example.sh`.
- [ ] **Step 4: Mac scripts.** `tools/mac-bootstrap.sh` gains a step that runs `tools/get-exiftool.sh`. `tools/mac-build.sh` gains a step `example check` running `tools/check-example.sh`, after `Core tests`. Write `tools/mac-check-session.sh`. `bash -n` on all four.
- [ ] **Step 5: Docs.** One paragraph in `README.md`; in `docs/guides/mac-setup.md`, how to check a session folder brought over from the phone.
- [ ] **Step 6: Run everything.** `swift test --package-path Core && (cd format && npm run validate) && tools/check-example.sh`. Expected: 110 tests, `SCHEMA CHECK OK (3 valid, 15 rejected)`, `EXAMPLE CHECK OK`.
- [ ] **Step 7: Commit and push; confirm the three automatic checks pass on GitHub.** `ci: check the worked example with the session checker`

---

### Task 8: Running the workbench's own reader over the example

**Files:**
- Create: `tools/workbench-check/scan.mts`, `tools/workbench-check.sh`, `docs/compatibility/workbench-check.md`
- Modify: `docs/superpowers/specs/2026-11-23-field-notebook-recorder-design.md` (section 6.4: add that the check has now been run, and link the record), `README.md`

**Interfaces:**
- Consumes: the example folder (Task 6); a local checkout of the workbench (`MaquisChat/AlexandrineOxiana`) with its dependencies installed.
- Produces: `tools/workbench-check.sh WORKBENCH_CHECKOUT SESSION_FOLDER`. Last line `WORKBENCH CHECK OK (<n> files, workbench <commit>)` or `WORKBENCH CHECK FAILED (...)`.

`scan.mts` is run with the workbench's own `tsx` from inside its checkout. It imports the workbench's `deviceAdapter` (`packages/library/src/import/device.ts`) and `extractExif` (`packages/library/src/extract/exif.ts`) by path, and:

0. (added while executing) compares folder names: `format/naming-cases.json`, written by a Swift test from a list of awkward titles, holds the folder name the recorder gives each; the workbench's `sanitizeSegment` must leave every one unchanged;
1. runs `deviceAdapter(SESSION_FOLDER, { researcherName: "R" }).scan(...)` to the end and records, for each item, its key, type, title, and each file's mime type, `capturedAt`, `tzOffset` and device;
2. runs `extractExif` on each media file and records the location it reports;
3. compares with `session.json`: every listed photo, clip and audio file arrived as exactly one item of the right type (`field-photo`, `field-video`, `field-recording`); nothing else arrived; each `capturedAt` is within a second of the manifest's instant; each `tzOffset` equals the manifest's; each location matches within the Global Constraints' tolerances, and is absent where the manifest has none; no item is a Live Photo pair;
4. prints one line per file (`ok` or `FAIL`, with what the workbench saw), then the verdict.

This is not part of the automatic checks, because it needs the workbench's code. It is run by hand when either side changes, and the result is written down.

- [ ] **Step 1: Write `scan.mts` and `workbench-check.sh`; run against the example.** Expected: every file `ok`, `WORKBENCH CHECK OK (6 files, workbench 0ad6506)`.
- [ ] **Step 2: Prove it bites.** Run it against a copy of the example in which one clip's Apple creation date has been removed. Expected `FAIL` for that clip (the workbench then has no time zone for it) and `WORKBENCH CHECK FAILED`.
- [ ] **Step 3: Write `docs/compatibility/workbench-check.md`:** the date, the workbench commit, the command, the full output, what it shows in plain language, and what it does not show (notes, placement beside the transcript and zip import are still the workbench project's work, spec section 9).
- [ ] **Step 4: Update spec 6.4 and `README.md`; commit and push.** `docs: the workbench's reader run over the worked example`
