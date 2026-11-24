# Stage 0 Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove on the owner's iPhone that session audio records without gaps through video clips, photos, backgrounding, locking and a phone call; find out how the iPad treats the owner's stylus; record both findings as decision records; then delete the test app.

**Architecture:** A throwaway SwiftUI app under `spike/`, generated with XcodeGen, plus a small pure-Swift package `spike/SpikeKit` that holds the logic producing the verdict (event log, gap analysis, audio position, report text) and is unit-tested. One `AVAudioEngine` owns the microphone and writes the session audio; a separate video-only `AVCaptureSession` handles photos and clips. Two ways of giving a clip sound are compared. Every test run writes a plain-text report.

**Tech Stack:** Swift (language mode 5), SwiftUI, AVFoundation, PencilKit, XCTest, XcodeGen, Xcode 27 command-line tools (`xcodebuild`, `xcrun devicectl`), bash.

**Spec:** `docs/superpowers/specs/2026-11-23-field-notebook-recorder-design.md` (stage 0 in section 7; constraints in section 3).

**Where this sits.** This is the first of several plans. Later plans, each written when it is next: foundations (session folder format, core library, session checker), stage 1 (iPhone app), stage 2 (video clips), stage 3 (iPad and stylus). The foundations plan does not depend on this one and can run alongside it.

## Global Constraints

- Every command marked **[Mac]** runs on the owner's Mac, in the repository folder. Cloud sessions cannot compile Swift or reach the devices. Run this plan from a Claude session on the Mac (Claude Desktop, or `claude remote-control` in the repository folder). If that is not possible, the owner runs the script named in the step and sends back the log file it names.
- Steps marked **[Owner]** need the owner's hands: signing in, tapping on a device, carrying out a test run.
- Mac: Apple silicon, macOS Tahoe 26.6 or later, Xcode 27. Devices: iPhone 17 Pro and iPad mini (6th generation), both on version 27.
- Deployment target: iOS and iPadOS 26.0.
- Swift language mode 5 for everything in this plan. Tests use XCTest.
- Free Apple developer account: automatic signing with the owner's Personal Team. An installed app stops launching after seven days, so the test runs in Task 8 must happen within seven days of the install, or the app is installed again.
- The repository is public. Never commit a person's name, an email address, a team id, a device name or a device identifier. The team id and bundle id prefix live only in `spike/Local.xcconfig`, which is not committed. Reports identify a device by hardware model and OS version only, never by `UIDevice.current.name`.
- Never commit audio, video or photos from test runs. Only `report.txt` files are committed.
- The app makes no network connections, writes nothing to the Photos library, and keeps its files in its own Documents folder.
- Spike code lives only under `spike/` and is deleted in Task 9. Nothing outside `spike/` may depend on it.
- Decision records go in `docs/adr/`, with the sections Status, Date, Context, Decision, Consequences.
- Work on a branch named `stage-0-spike`. Do not commit to `main` directly.

## Review Focus

Failure modes the spec implies that are most likely to bite, each pinned by a test or check in the task named:

1. **A headset connects mid-recording** (AirPods pair on their own). Recording must carry on from the built-in microphone, with the route change logged. Pinned by run R9 (Task 8) and the route-change event (Task 5).
2. **Microphone permission is refused.** The app must say so and create no run, never produce a report that looks like a quiet recording. Pinned by the permission check in Task 5 and by `testNoBuffersIsNoAudioNotContinuous` (Task 3).
3. **The engine restarts and its sample numbering begins again at zero.** The analysis must report a restart with the real missing time, not a huge negative gap. Pinned by `testEngineRestartIsARestartNotANegativeGap` (Task 2).
4. **A run is cut off by a crash or force-quit.** The last line of a log file may be half written; the report must still be produced, marked UNFINISHED. Pinned by `testTruncatedLastLineIsSkipped` (Task 3) and run R10 (Task 8).
5. **Writing audio fails part-way** (storage full). The run must stop and say why, not keep counting audio it did not save. Pinned by the write-failure switch check in Task 5.

---

## Execution status (2026-11-24)

Worked so far in a cloud session on Linux. **Nothing has run on the Mac or on a device yet.** Ticked steps below are done; unticked steps need the Mac, the devices or the owner.

- **Tasks 2 and 3 are complete.** SpikeKit's 16 tests were watched failing, then passing, with Swift 6.4.3 on Linux. `tools/mac-build.sh` runs them again on the Mac.
- **Tasks 1, 4, 5, 6, 7 and 8 are written and committed but not verified.** The app code under `spike/App/` has never been compiled against Apple's SDKs. It passes a syntax check, and it type-checks against hand-written stand-ins for Apple's modules, which proves the Swift is consistent but not that every Apple API is spelled as the real SDK spells it. Expect to fix compile errors at Task 4 step 6.
- **The scripts were exercised with stand-in commands** (version checks, signing-team capture, device selection, log scrubbing, the XcodeGen download and checksum). Not confirmed on a Mac: every `xcrun devicectl` call, and in particular whether `device copy from` copies a whole folder (`tools/mac-fetch-results.sh` says so at the top).
- **Task 9 has not started.** It is written from the device results.
- Two independent reviews of the unverified code were done and their findings fixed (commits "review fixes").

**To resume on the Mac:** do Task 1 steps 7 and 8, then continue from the first unticked step of each task in order.

**Decisions taken while executing, where they differ from the text below:**

1. `tools/mac-lib.sh` was added: shared device lookup (`find_device`), a `scrub` filter that removes identifiers, names, the signing team and the home folder from everything the scripts print or log, and `use_installed_xcode`.
2. XcodeGen is pinned to 2.46.0 with its checksum recorded. Its support for Xcode 27 projects is not confirmed; raise the version on the Mac if generation fails.
3. `spike/project.yml` has `scheme: {}` so that `xcodebuild -scheme Spike` has a scheme to find. `.gitignore` also ignores `.swiftpm/` and `xcuserdata/`.
4. `RunStore.deviceLine` works out "iOS" or "iPadOS" from the hardware model and takes the version from `ProcessInfo`, not `UIDevice`.
5. `AudioRunner.micAllowed()` was added; the view asks it before creating a run folder, so a refusal creates nothing.
6. The report is written when recording ends for any reason, not only from the Stop button, and only after any clip-sound attempt has finished.
7. Clip sound is added in two attempts: straight after the clip (`clip-muxed … when=during-run`, or `clip-mux-early-failed`) and again after the run stops (`when=after-stop`, or `clip-mux-failed`). Whether the session audio can be read while it is still being written is itself a finding for the audio decision in Task 9.
8. The camera asks for camera permission when opened, and its clip and photo numbers restart with each run.
9. Launch recovery also writes the report for a run that finished cleanly but was closed before its report was written.
10. `tools/mac-install.sh` reports "installed but could not be opened" with what to do, since the first launch fails until the owner trusts the developer app on the device.

---

## File Structure

```
README.md                         what this repository is, in a few lines
.gitignore
tools/
  mac-bootstrap.sh                checks macOS and Xcode, fetches XcodeGen, writes Local.xcconfig
  mac-build.sh                    runs SpikeKit tests, generates the project, builds for a device
  mac-install.sh                  installs and launches the built app on a connected device
  mac-fetch-results.sh            copies report.txt files from the device into docs/spike/results/
docs/
  guides/mac-setup.md             the owner's one-time setup, in plain language
  spike/test-protocol.md          the runs the owner carries out, step by step
  spike/results/<model>/<run>/report.txt
  adr/0000-template.md
  adr/0001-audio-pipeline.md
  adr/0002-stylus-input.md
spike/                            (deleted in Task 9)
  project.yml                     XcodeGen project definition
  Local.xcconfig.example
  SpikeKit/
    Package.swift
    Sources/SpikeKit/EventLog.swift        timestamped events
    Sources/SpikeKit/GapAnalyzer.swift     BufferRecord, Gap, gap detection, AudioPosition
    Sources/SpikeKit/ReportWriter.swift    RunSummary, report text
    Sources/SpikeKit/JSONLines.swift       one-JSON-object-per-line reading and writing
    Tests/SpikeKitTests/…Tests.swift
  App/
    SpikeApp.swift                app entry, three tabs
    RunStore.swift                run folders and files, device line, report generation
    AudioRunner.swift             audio session, engine tap, file writing, notifications
    CameraController.swift        video-only capture session, photos, clips
    ClipMuxer.swift               adds session audio to a silent clip
    AudioTestView.swift           controls for a run
    ReportsView.swift             list of runs, report text, share
    StylusProbeView.swift         touch-type probe and drawing canvas (iPad)
```

---

### Task 1: Repository basics and Mac toolchain

**Files:**
- Create: `README.md`, `.gitignore`, `tools/mac-bootstrap.sh`, `spike/Local.xcconfig.example`, `docs/guides/mac-setup.md`, `docs/adr/0000-template.md`

**Interfaces:**
- Produces: `tools/mac-bootstrap.sh` (exit 0 and last line `BOOTSTRAP OK` on success); `.tools/xcodegen/bin/xcodegen`; `spike/Local.xcconfig` defining `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX`.

- [x] **Step 1: Write `.gitignore`**

```
.DS_Store
.build/
.swiftpm/
xcuserdata/
.tools/
build/
spike/Spike.xcodeproj/
spike/Generated/
spike/Local.xcconfig
docs/spike/results/**/*.caf
docs/spike/results/**/*.mov
docs/spike/results/**/*.heic
docs/spike/results/**/*.jsonl
```

- [x] **Step 2: Write `README.md`**

Four short paragraphs: what the app is (one sentence from the spec's Purpose); that the design is in `docs/superpowers/specs/`; that plans are in `docs/superpowers/plans/`; that building needs a Mac and starts with `docs/guides/mac-setup.md`.

- [x] **Step 3: Write `spike/Local.xcconfig.example`**

```
// Copy to Local.xcconfig. tools/mac-bootstrap.sh does this for you.
DEVELOPMENT_TEAM =
BUNDLE_ID_PREFIX = local.scrivner.example
```

- [x] **Step 4: Write `tools/mac-bootstrap.sh`**

Behaviour, in order, stopping with a one-line plain-language message and exit 1 at the first failure:
1. `sw_vers -productVersion` is 26.6 or later.
2. `xcodebuild -version` reports Xcode 27 or later.
3. If `.tools/xcodegen/bin/xcodegen` is missing, download `https://github.com/yonaskolb/XcodeGen/releases/download/$XCODEGEN_VERSION/xcodegen.zip` into `.tools/` and unzip it. Set `XCODEGEN_VERSION` at the top of the script to the newest release on the day this task is done, and after the first download record the zip's SHA-256 in `XCODEGEN_SHA256` and verify it on every later download.
4. If `spike/Local.xcconfig` is missing, create it with `DEVELOPMENT_TEAM =` (empty) and `BUNDLE_ID_PREFIX = local.scrivner.<8 random lower-case hex characters>`.
5. With `--capture-team`: read the `DEVELOPMENT_TEAM` value from `spike/Spike.xcodeproj/project.pbxproj` and write it into `spike/Local.xcconfig`; fail if none is found.
6. Print the macOS, Xcode and XcodeGen versions, then `BOOTSTRAP OK`.

- [x] **Step 5: Write `docs/guides/mac-setup.md`**

Plain language, numbered, one action per step, for a reader who does not code:
1. Update macOS to Tahoe 26.6 or later (System Settings, General, Software Update).
2. Install Xcode 27 from the App Store; open it once, accept the licence, and install the iOS platform when asked.
3. In Xcode: Settings, Accounts, add your Apple Account (the free account is enough).
4. Connect the iPhone by cable and tap Trust. Then on the iPhone: Settings, Privacy & Security, Developer Mode, on. Repeat for the iPad.
5. Open the repository folder in a Claude session on the Mac so Claude can run the builds.
6. What happens the first time the app is installed: on the device, Settings, General, VPN & Device Management, trust the developer app.
7. The seven-day limit and what re-installing means.
8. Choosing the signing team once (the wording of Task 4 Step 7).

- [x] **Step 6: Write `docs/adr/0000-template.md`**

Headings only: `# NNNN. Title`, `- **Status:**`, `- **Date:**`, `## Context`, `## Decision`, `## Consequences`.

- [ ] **Step 7: [Owner] Carry out steps 1 to 5 of `docs/guides/mac-setup.md`**

- [ ] **Step 8: [Mac] Run the bootstrap**

Run: `tools/mac-bootstrap.sh`
Expected: last line `BOOTSTRAP OK`; `spike/Local.xcconfig` exists; `git status` does not list it.

- [x] **Step 9: Commit**

```bash
git add README.md .gitignore tools/mac-bootstrap.sh spike/Local.xcconfig.example docs/guides/mac-setup.md docs/adr/0000-template.md
git commit -m "chore: repository basics and Mac toolchain bootstrap"
```

---

### Task 2: SpikeKit events, gap analysis and audio position

**Files:**
- Create: `spike/SpikeKit/Package.swift`, `spike/SpikeKit/Sources/SpikeKit/EventLog.swift`, `spike/SpikeKit/Sources/SpikeKit/GapAnalyzer.swift`
- Test: `spike/SpikeKit/Tests/SpikeKitTests/EventLogTests.swift`, `spike/SpikeKit/Tests/SpikeKitTests/GapAnalyzerTests.swift`

**Interfaces:**
- Produces:

```swift
public struct SpikeEvent: Codable, Equatable, Sendable {
    public let hostSeconds: Double   // monotonic clock, seconds
    public let wall: Date
    public let kind: String          // e.g. "clip-start"
    public let detail: String
    public init(hostSeconds: Double, wall: Date, kind: String, detail: String)
}
public final class EventLog: @unchecked Sendable {
    public init(clock: @escaping () -> (hostSeconds: Double, wall: Date),
                sink: ((SpikeEvent) -> Void)? = nil)             // sink is called for every event, after it is stored
    public func record(_ kind: String, _ detail: String = "")    // safe to call from any thread; reads the clock exactly once
    public var events: [SpikeEvent] { get }
}
public struct BufferRecord: Codable, Equatable, Sendable {
    public let sampleTime: Int64     // sample number of the buffer's first frame
    public let frames: Int
    public let hostSeconds: Double   // monotonic time of the buffer's first frame
    public init(sampleTime: Int64, frames: Int, hostSeconds: Double)
}
public enum GapKind: String, Codable, Sendable { case sampleJump, hostJump, restart }
public struct Gap: Equatable, Sendable {
    public let afterBufferIndex: Int
    public let atHostSeconds: Double    // when the previous buffer ended
    public let missingSeconds: Double
    public let kind: GapKind
    public init(afterBufferIndex: Int, atHostSeconds: Double, missingSeconds: Double, kind: GapKind)
}
public enum GapAnalyzer {
    public static func gaps(in buffers: [BufferRecord], sampleRate: Double, toleranceSeconds: Double = 0.010) -> [Gap]
}
public enum AudioPosition {
    /// Seconds into the audio file for a monotonic time, or nil if no buffer covers that time.
    public static func seconds(atHost host: Double, buffers: [BufferRecord], sampleRate: Double) -> Double?
}
```

- [x] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpikeKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [.library(name: "SpikeKit", targets: ["SpikeKit"])],
    targets: [
        .target(name: "SpikeKit"),
        .testTarget(name: "SpikeKitTests", dependencies: ["SpikeKit"]),
    ],
    swiftLanguageModes: [.v5]
)
```

- [x] **Step 2: Write the failing tests**

`GapAnalyzerTests.swift`:

```swift
import XCTest
@testable import SpikeKit

final class GapAnalyzerTests: XCTestCase {
    let sr = 48_000.0
    func buf(_ sample: Int64, _ host: Double, frames: Int = 4800) -> BufferRecord {
        BufferRecord(sampleTime: sample, frames: frames, hostSeconds: host)
    }

    func testContiguousBuffersHaveNoGaps() {
        XCTAssertEqual(GapAnalyzer.gaps(in: [buf(0, 10.0), buf(4800, 10.1), buf(9600, 10.2)], sampleRate: sr), [])
    }
    func testSampleJumpIsReportedWithMissingTime() {
        let g = GapAnalyzer.gaps(in: [buf(0, 10.0), buf(52_800, 11.1)], sampleRate: sr)
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].kind, .sampleJump)
        XCTAssertEqual(g[0].afterBufferIndex, 0)
        XCTAssertEqual(g[0].atHostSeconds, 10.1, accuracy: 1e-9)
        XCTAssertEqual(g[0].missingSeconds, 1.0, accuracy: 1e-9)
    }
    func testHostJumpWithContinuousSamplesIsReported() {
        let g = GapAnalyzer.gaps(in: [buf(0, 10.0), buf(4800, 12.6)], sampleRate: sr)
        XCTAssertEqual(g.map(\.kind), [.hostJump])
        XCTAssertEqual(g[0].missingSeconds, 2.5, accuracy: 1e-9)
    }
    func testEngineRestartIsARestartNotANegativeGap() {
        let g = GapAnalyzer.gaps(in: [buf(96_000, 10.0), buf(0, 13.1)], sampleRate: sr)
        XCTAssertEqual(g.map(\.kind), [.restart])
        XCTAssertEqual(g[0].missingSeconds, 3.0, accuracy: 1e-9)
    }
    func testJitterWithinToleranceIsIgnored() {
        XCTAssertEqual(GapAnalyzer.gaps(in: [buf(0, 10.0), buf(4800, 10.105)], sampleRate: sr), [])
    }
    func testPositionInsideSecondBuffer() {
        let p = AudioPosition.seconds(atHost: 10.15, buffers: [buf(0, 10.0), buf(4800, 10.1)], sampleRate: sr)
        XCTAssertEqual(p!, 0.15, accuracy: 1e-9)
    }
    func testPositionAfterAGapCountsOnlyRecordedAudio() {
        let p = AudioPosition.seconds(atHost: 12.65, buffers: [buf(0, 10.0), buf(4800, 12.6)], sampleRate: sr)
        XCTAssertEqual(p!, 0.15, accuracy: 1e-9)
    }
    func testPositionInsideAGapOrBeforeStartIsNil() {
        let b = [buf(0, 10.0), buf(4800, 12.6)]
        XCTAssertNil(AudioPosition.seconds(atHost: 11.0, buffers: b, sampleRate: sr))
        XCTAssertNil(AudioPosition.seconds(atHost: 9.0, buffers: b, sampleRate: sr))
    }
}
```

`EventLogTests.swift`:

```swift
import XCTest
@testable import SpikeKit

final class EventLogTests: XCTestCase {
    func testEventsAreStoredInOrderAndSentToTheSink() {
        var t = 100.0
        var sunk: [String] = []
        let log = EventLog(clock: { t += 1; return (t, Date(timeIntervalSince1970: t)) },
                           sink: { sunk.append($0.kind) })
        log.record("audio-start")
        log.record("clip-start", "mux")
        XCTAssertEqual(log.events.map(\.kind), ["audio-start", "clip-start"])
        XCTAssertEqual(log.events[1].detail, "mux")
        XCTAssertEqual(log.events[0].hostSeconds, 101.0)
        XCTAssertEqual(sunk, ["audio-start", "clip-start"])
    }
}
```

- [x] **Step 3: [Mac] Run the tests to see them fail**

Run: `swift test --package-path spike/SpikeKit`
Expected: build failure naming `GapAnalyzer`, `AudioPosition` and `EventLog` as undefined.

- [x] **Step 4: Implement `EventLog.swift` and `GapAnalyzer.swift`**

`EventLog` guards its array with an `NSLock`.

`GapAnalyzer.gaps`: for each consecutive pair `a`, `b`, with `aEnd = a.hostSeconds + Double(a.frames) / sampleRate`, `sampleDelta = b.sampleTime - (a.sampleTime + Int64(a.frames))` and `hostHole = b.hostSeconds - aEnd`, apply the first rule that matches:
1. `sampleDelta < 0`: a `.restart` with `missingSeconds = max(hostHole, 0)`.
2. `sampleDelta > 0`: a `.sampleJump` with `missingSeconds = Double(sampleDelta) / sampleRate`.
3. `hostHole > toleranceSeconds`: a `.hostJump` with `missingSeconds = hostHole`.
4. Otherwise no gap.

Every gap has `atHostSeconds = aEnd` and `afterBufferIndex` = the index of `a`.

`AudioPosition.seconds`: find the buffer whose span `[hostSeconds, hostSeconds + frames / sampleRate)` contains `host`; return the frames of all earlier buffers divided by `sampleRate`, plus `host - buffer.hostSeconds`.

- [x] **Step 5: [Mac] Run the tests to see them pass**

Run: `swift test --package-path spike/SpikeKit`
Expected: `Executed 9 tests, with 0 failures`.

- [x] **Step 6: Commit**

```bash
git add spike/SpikeKit
git commit -m "feat(spike): event log, gap analysis and audio position"
```

---

### Task 3: SpikeKit report text and line-by-line files

**Files:**
- Create: `spike/SpikeKit/Sources/SpikeKit/ReportWriter.swift`, `spike/SpikeKit/Sources/SpikeKit/JSONLines.swift`
- Test: `spike/SpikeKit/Tests/SpikeKitTests/ReportWriterTests.swift`, `spike/SpikeKit/Tests/SpikeKitTests/JSONLinesTests.swift`

**Interfaces:**
- Consumes: `SpikeEvent`, `BufferRecord`, `Gap`, `GapAnalyzer.gaps` from Task 2.
- Produces:

```swift
public enum RunStatus: String, Sendable { case finished = "FINISHED", unfinished = "UNFINISHED" }
public struct RunSummary: Equatable, Sendable {
    public let wallSeconds: Double        // end of last buffer minus start of first; 0 with no buffers
    public let recordedSeconds: Double    // total frames / sampleRate
    public let gaps: [Gap]
    public let largestGapSeconds: Double  // 0 with no gaps
    public init(wallSeconds: Double, recordedSeconds: Double, gaps: [Gap], largestGapSeconds: Double)
}
public enum ReportWriter {
    public static func summary(buffers: [BufferRecord], sampleRate: Double, toleranceSeconds: Double = 0.010) -> RunSummary
    public static func text(title: String, device: String, status: RunStatus, summary: RunSummary,
                            events: [SpikeEvent], startHostSeconds: Double, nearWindowSeconds: Double = 2.0) -> String
}
public enum JSONLines {
    public static func encodeLine<T: Encodable>(_ value: T) throws -> String            // one line, no newline
    public static func decode<T: Decodable>(_ type: T.Type, from text: String) -> (items: [T], skippedLines: Int)
}
```

- [x] **Step 1: Write the failing tests**

`ReportWriterTests.swift`:

```swift
import XCTest
@testable import SpikeKit

final class ReportWriterTests: XCTestCase {
    func testSummaryCountsWallAndRecordedTime() {
        let b = [BufferRecord(sampleTime: 0, frames: 4800, hostSeconds: 10.0),
                 BufferRecord(sampleTime: 52_800, frames: 4800, hostSeconds: 11.1)]
        let s = ReportWriter.summary(buffers: b, sampleRate: 48_000)
        XCTAssertEqual(s.wallSeconds, 1.2, accuracy: 1e-9)
        XCTAssertEqual(s.recordedSeconds, 0.2, accuracy: 1e-9)
        XCTAssertEqual(s.gaps.count, 1)
        XCTAssertEqual(s.largestGapSeconds, 1.0, accuracy: 1e-9)
    }

    func testReportTextIsExact() {
        let s = RunSummary(wallSeconds: 181.0, recordedSeconds: 180.0,
                           gaps: [Gap(afterBufferIndex: 650, atHostSeconds: 1065.1, missingSeconds: 1.0, kind: .sampleJump)],
                           largestGapSeconds: 1.0)
        let ev = [SpikeEvent(hostSeconds: 1000.0, wall: Date(timeIntervalSince1970: 0), kind: "audio-start", detail: ""),
                  SpikeEvent(hostSeconds: 1065.0, wall: Date(timeIntervalSince1970: 65), kind: "clip-start", detail: "mux")]
        let t = ReportWriter.text(title: "R5 clip mux", device: "iPhone18,1 iOS 27.1", status: .finished,
                                  summary: s, events: ev, startHostSeconds: 1000.0)
        XCTAssertEqual(t, """
        SPIKE REPORT R5 clip mux
        device: iPhone18,1 iOS 27.1
        status: FINISHED
        wall seconds: 181.0
        recorded seconds: 180.0
        gaps: 1
        largest gap seconds: 1.000
        VERDICT continuous: NO
        EVENTS
        +0.000 audio-start
        +65.000 clip-start mux
        GAPS
        +65.100 sampleJump missing 1.000s near: clip-start(+65.000)

        """)
    }

    func testNoGapsIsContinuousAndListsNone() {
        let s = RunSummary(wallSeconds: 60, recordedSeconds: 60, gaps: [], largestGapSeconds: 0)
        let t = ReportWriter.text(title: "R1", device: "d", status: .finished, summary: s, events: [], startHostSeconds: 0)
        XCTAssertTrue(t.contains("VERDICT continuous: YES\n"))
        XCTAssertTrue(t.contains("EVENTS\n(none)\nGAPS\n(none)\n"))
    }

    func testNoBuffersIsNoAudioNotContinuous() {
        let s = ReportWriter.summary(buffers: [], sampleRate: 48_000)
        XCTAssertEqual(s.recordedSeconds, 0)
        let t = ReportWriter.text(title: "R1", device: "d", status: .finished, summary: s, events: [], startHostSeconds: 0)
        XCTAssertTrue(t.contains("VERDICT continuous: NO AUDIO\n"))
    }

    func testUnfinishedStatusIsShown() {
        let s = RunSummary(wallSeconds: 60, recordedSeconds: 60, gaps: [], largestGapSeconds: 0)
        let t = ReportWriter.text(title: "R10", device: "d", status: .unfinished, summary: s, events: [], startHostSeconds: 0)
        XCTAssertTrue(t.contains("status: UNFINISHED\n"))
    }
}
```

`JSONLinesTests.swift`:

```swift
import XCTest
@testable import SpikeKit

final class JSONLinesTests: XCTestCase {
    func testRoundTrip() throws {
        let a = BufferRecord(sampleTime: 0, frames: 4800, hostSeconds: 10.0)
        let b = BufferRecord(sampleTime: 4800, frames: 4800, hostSeconds: 10.1)
        let text = try [a, b].map(JSONLines.encodeLine).joined(separator: "\n") + "\n"
        let r = JSONLines.decode(BufferRecord.self, from: text)
        XCTAssertEqual(r.items, [a, b])
        XCTAssertEqual(r.skippedLines, 0)
    }
    func testTruncatedLastLineIsSkipped() throws {
        let a = BufferRecord(sampleTime: 0, frames: 4800, hostSeconds: 10.0)
        let text = try JSONLines.encodeLine(a) + "\n{\"sampleTime\":48"
        let r = JSONLines.decode(BufferRecord.self, from: text)
        XCTAssertEqual(r.items, [a])
        XCTAssertEqual(r.skippedLines, 1)
    }
}
```

- [x] **Step 2: [Mac] Run the tests to see them fail**

Run: `swift test --package-path spike/SpikeKit`
Expected: build failure naming `ReportWriter` and `JSONLines` as undefined.

- [x] **Step 3: Implement `ReportWriter.swift` and `JSONLines.swift`**

Report rules, which the exact-text test pins:
- `wall seconds` and `recorded seconds` use one decimal place; every offset and gap length uses three.
- The verdict is `NO AUDIO` when `recordedSeconds == 0`, else `YES` when there are no gaps, else `NO`.
- An event line is `+<offset> <kind>`, followed by a space and the detail when the detail is not empty. Offsets are `hostSeconds - startHostSeconds`.
- A gap line is `+<offset> <kind> missing <seconds>s`, followed by ` near: ` and a comma-separated list of `<kind>(+<offset>)` for every event within `nearWindowSeconds` of the gap's `atHostSeconds`, when there are any.
- `(none)` stands in for an empty EVENTS or GAPS list. The text ends with a newline.

`JSONLines.encodeLine` uses `JSONEncoder` with sorted keys and dates as seconds since 1970. `decode` splits on newlines, ignores empty lines, and counts lines that fail to decode.

- [x] **Step 4: [Mac] Run the tests to see them pass**

Run: `swift test --package-path spike/SpikeKit`
Expected: `Executed 16 tests, with 0 failures`.

- [x] **Step 5: Commit**

```bash
git add spike/SpikeKit
git commit -m "feat(spike): report text and line-by-line log files"
```

---

### Task 4: App shell, build and install

**Files:**
- Create: `spike/project.yml`, `spike/App/SpikeApp.swift`, `spike/App/RunStore.swift`, `spike/App/ReportsView.swift`, `tools/mac-build.sh`, `tools/mac-install.sh`

**Interfaces:**
- Consumes: `ReportWriter`, `JSONLines`, `RunStatus`, `BufferRecord`, `SpikeEvent` from Tasks 2 and 3; `.tools/xcodegen/bin/xcodegen` and `spike/Local.xcconfig` from Task 1.
- Produces:

```swift
struct RunFolder: Identifiable, Hashable {
    let url: URL                 // Documents/runs/<yyyyMMdd-HHmmss>-<label>/
    var id: String { url.lastPathComponent }
    var audio: URL               // audio.caf
    var buffers: URL             // buffers.jsonl, one BufferRecord per line
    var events: URL              // events.jsonl, one SpikeEvent per line
    var report: URL              // report.txt
    var finishedMarker: URL      // empty file named "finished", written at a clean stop
    var clips: URL               // clips/
    var photos: URL              // photos/
}
enum RunStore {
    static func runsRoot() -> URL
    static func create(label: String, now: Date = Date()) throws -> RunFolder   // label keeps only A-Z a-z 0-9 and "-"
    static func all() -> [RunFolder]                                              // newest first
    static func appendLine(_ line: String, to url: URL)                           // appends the line and "\n"
    static func writeReport(for run: RunFolder, title: String) throws -> String   // builds report.txt from the files on disk
    static func deviceLine() -> String   // "<hardware model> <system name> <system version>", e.g. "iPhone18,1 iOS 27.1"
}
enum HostClock {
    static func now() -> Double          // AVAudioTime.seconds(forHostTime: mach_absolute_time()); the one clock every event uses
}
```

Scripts: `tools/mac-build.sh` checks that everything compiles, without signing, and ends with `RESULT: OK` or `RESULT: FAILED at <step>, log: <path>`. `tools/mac-install.sh iphone|ipad` builds signed for that device, installs and launches, and ends with `RESULT: INSTALLED on <hardware model>` or `RESULT: FAILED at <step>, log: <path>`.

- [x] **Step 1: Write `spike/project.yml`**

```yaml
name: Spike
options:
  deploymentTarget:
    iOS: "26.0"
configFiles:
  Debug: Local.xcconfig
  Release: Local.xcconfig
packages:
  SpikeKit:
    path: SpikeKit
targets:
  Spike:
    type: application
    platform: iOS
    scheme: {}
    sources: [App]
    dependencies:
      - package: SpikeKit
    info:
      path: Generated/Info.plist
      properties:
        UIBackgroundModes: [audio]
        NSMicrophoneUsageDescription: Records audio for the recording test.
        NSCameraUsageDescription: Takes photos and video for the recording test.
        UIFileSharingEnabled: true
        LSSupportsOpeningDocumentsInPlace: true
        UILaunchScreen: {}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).spike
        SWIFT_VERSION: "5.0"
        TARGETED_DEVICE_FAMILY: "1,2"
        CODE_SIGN_STYLE: Automatic
```

- [x] **Step 2: Implement `RunStore.swift`**

`HostClock` lives in this file. `writeReport` reads `buffers.jsonl` and `events.jsonl` with `JSONLines.decode`, takes the sample rate from `audio.caf` (48 000 if the file cannot be opened), uses the first buffer's `hostSeconds` as the start (the first event's when there are no buffers), sets the status from whether `finishedMarker` exists, and adds one extra line at the end of the report: `log lines skipped: <n>`. `deviceLine` reads the hardware model with `sysctlbyname("hw.machine")`.

- [x] **Step 3: Implement `SpikeApp.swift` and `ReportsView.swift`**

`SpikeApp`: a `TabView` with three tabs titled "Audio test", "Stylus", "Reports". The first two show placeholder text until Tasks 5 and 7. On launch, for every run folder with neither `finished` nor `report.txt`, append an event `recovered-at-launch` whose detail is `readable-seconds=<seconds of audio.caf that can be opened, or "unreadable">`, then call `writeReport`.

`ReportsView`: lists `RunStore.all()` by folder name; selecting one shows `report.txt` in a monospaced, selectable `Text` inside a `ScrollView`, with a `ShareLink` for the report file.

- [x] **Step 4: Write `tools/mac-build.sh`**

Steps, each logged to `build/logs/build-<yyyyMMdd-HHmmss>.log` as well as the screen:
1. `tools/mac-bootstrap.sh`
2. `swift test --package-path spike/SpikeKit`
3. `(cd spike && ../.tools/xcodegen/bin/xcodegen generate)`
4. `xcodebuild -project spike/Spike.xcodeproj -scheme Spike -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build`

Stop at the first failing step and print the `RESULT:` line described under Interfaces.

- [x] **Step 5: Write `tools/mac-install.sh`**

Takes `iphone` or `ipad`, and logs to `build/logs/install-<yyyyMMdd-HHmmss>.log`. Steps:
1. Find the connected device of that kind and its identifier with `xcrun devicectl list devices`.
2. `xcodebuild -project spike/Spike.xcodeproj -scheme Spike -destination "platform=iOS,id=<identifier>" -derivedDataPath build/DerivedData -allowProvisioningUpdates -allowProvisioningDeviceRegistration build`
3. Install `build/DerivedData/Build/Products/Debug-iphoneos/Spike.app` with `xcrun devicectl device install app`.
4. Launch it with `xcrun devicectl device process launch`, using the bundle identifier read from the built app's `Info.plist`.

Confirm the exact flags with `xcrun devicectl help device install app` and `xcrun devicectl help device process launch` before writing them. Print the hardware model, never the device's name or identifier.

- [ ] **Step 6: [Mac] Check it compiles**

Run: `tools/mac-build.sh`
Expected: last line `RESULT: OK`.

- [ ] **Step 7: [Owner] Choose the signing team once**

Open `spike/Spike.xcodeproj` in Xcode, select the Spike target, open Signing & Capabilities, and choose the team ending in "(Personal Team)". Close Xcode. Then run `tools/mac-bootstrap.sh --capture-team`.
Expected: `BOOTSTRAP OK`, and `spike/Local.xcconfig` now has a ten-character `DEVELOPMENT_TEAM`.

- [ ] **Step 8: [Mac] [Owner] Install on both devices**

Run: `tools/mac-install.sh iphone`, then `tools/mac-install.sh ipad`, each with that device connected and unlocked. The first time, the owner trusts the developer app on each device (guide step 6).
Expected: `RESULT: INSTALLED on …` twice; the app opens on each device showing the three tabs, and Reports is empty.
If signing fails from the command line: the owner opens the project in Xcode, picks the device in the toolbar and presses Run once per device, which registers the device; then run the script again.

- [x] **Step 9: Commit**

```bash
git add spike/project.yml spike/App tools/mac-build.sh tools/mac-install.sh
git commit -m "feat(spike): app shell with run storage, build and install scripts"
```

---

### Task 5: Session audio

**Files:**
- Create: `spike/App/AudioRunner.swift`, `spike/App/AudioTestView.swift`
- Modify: `spike/App/SpikeApp.swift` (first tab shows `AudioTestView`)

**Interfaces:**
- Consumes: `EventLog`, `BufferRecord`, `JSONLines.encodeLine` (Tasks 2, 3); `RunFolder`, `RunStore`, `HostClock` (Task 4).
- Produces:

```swift
enum MicError: Error { case denied }
final class AudioRunner: ObservableObject {
    @Published private(set) var isRunning: Bool
    @Published private(set) var recordedSeconds: Double
    @Published private(set) var lastProblem: String?
    private(set) var log: EventLog?        // set by start, with HostClock.now() as its clock; every event is also appended to the run's events.jsonl
    private(set) var sampleRate: Double
    var failWritesAfterSeconds: Double?    // test switch: when set, writes fail after this much recorded audio
    func start(in run: RunFolder) async throws   // throws MicError.denied when access is not granted
    func stop()                                   // writes the finished marker
}
```

- [x] **Step 1: Implement `AudioRunner.swift`**

Pinned choices:
- Audio session: category `.record`, mode `.default`, no options (in particular not `.allowBluetooth`); `setPrefersNoInterruptionsFromSystemAlerts(true)`; then `setActive(true)`.
- Permission: request record permission in `start`; if it is not granted, throw `MicError.denied` before creating any file.
- Capture: `engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNode.outputFormat(forBus: 0))`. For each buffer: write it to an `AVAudioFile` at `run.audio` created with the input format's settings; append a `BufferRecord(sampleTime: time.sampleTime, frames: Int(buffer.frameLength), hostSeconds: AVAudioTime.seconds(forHostTime: time.hostTime))` line to `run.buffers`.
- Events, each recorded with these exact kinds: `audio-start`, `audio-stop`, `interruption-began`, `interruption-ended` (detail `should-resume` or `no-resume`), `route-change` (detail: the reason's name), `media-services-reset`, `engine-config-change`, `engine-restart-ok`, `engine-restart-failed` (detail: the error), `did-enter-background`, `will-enter-foreground`, `protected-data-unavailable`, `protected-data-available`, `audio-write-failed` (detail: the error).
- Recovery: on `interruption-ended` (whatever its options), on `engine-config-change`, and on the app becoming active while a run is meant to be running, try to activate the session and start the engine again, recording `engine-restart-ok` or `engine-restart-failed`.
- Write failure: a failed write, or reaching `failWritesAfterSeconds`, records `audio-write-failed`, sets `lastProblem`, and stops the run.

- [x] **Step 2: Implement `AudioTestView.swift`**

A form with: a run-label picker (`R1` to `R12`); Start and Stop buttons; a live readout of recorded seconds; `lastProblem` in red when set; a "Fail writes after 10 s (test)" toggle. Stop calls `RunStore.writeReport` with the label as title. When `start` throws `MicError.denied`, show exactly: `Microphone access is off. Turn it on in Settings, Privacy & Security, Microphone.` and create no run folder. Leave room below for the camera controls of Task 6.

- [ ] **Step 3: [Mac] Build and install**

Run: `tools/mac-build.sh && tools/mac-install.sh iphone`
Expected: `RESULT: OK` then `RESULT: INSTALLED on …`.

- [ ] **Step 4: [Owner] Check permission refusal**

On first Start, tap "Don't Allow".
Expected: the message from Step 2; Reports stays empty. Then turn the microphone on for Spike in Settings.

- [ ] **Step 5: [Owner] Check a plain run and a locked run**

Label R1: Start, wait 60 seconds, Stop. Label R2: Start, lock the phone for 60 seconds, unlock, Stop.
Expected: both reports show `VERDICT continuous: YES`, with `recorded seconds` within 1.0 of `wall seconds`.

- [ ] **Step 6: [Owner] Check the write-failure switch**

Turn on "Fail writes after 10 s (test)", label R1, Start, wait 20 seconds.
Expected: the run stops by itself, the problem is shown in red, and the report lists an `audio-write-failed` event with `recorded seconds` close to 10.

- [x] **Step 7: Commit**

```bash
git add spike/App
git commit -m "feat(spike): session audio with gap logging and recovery"
```

---

### Task 6: Photos, clips and clip sound

**Files:**
- Create: `spike/App/CameraController.swift`, `spike/App/ClipMuxer.swift`
- Modify: `spike/App/AudioTestView.swift` (camera controls)

**Interfaces:**
- Consumes: `EventLog`, `AudioPosition.seconds`, `JSONLines.decode` (Tasks 2, 3); `RunFolder`, `HostClock` (Task 4); `AudioRunner` and its `log` (Task 5).
- Produces:

```swift
enum ClipSound: String, CaseIterable { case muxAfter = "mux", sessionMic = "session-mic" }
final class CameraController: NSObject, ObservableObject {
    let session: AVCaptureSession
    @Published private(set) var isOpen: Bool
    @Published private(set) var isRecordingClip: Bool
    func open(log: EventLog)
    func close()
    func takePhoto(into run: RunFolder, quietShutter: Bool)
    func startClip(into run: RunFolder, sound: ClipSound)
    func stopClip()
    /// Called when a clip file is complete: the file, the monotonic time its first frame was captured, its length, and how it was recorded.
    var onClipFinished: ((URL, Double, Double, ClipSound) -> Void)?
}
enum ClipMuxer {
    static func mux(clip: URL, sessionAudio: URL, audioStartSeconds: Double, durationSeconds: Double, output: URL) async throws
}
```

- [x] **Step 1: Implement `CameraController.swift`**

Pinned choices:
- `session.automaticallyConfiguresApplicationAudioSession = false`, preset `.high`, back wide-angle camera, one `AVCaptureMovieFileOutput` and one `AVCapturePhotoOutput`. All session work on one serial queue.
- `ClipSound.muxAfter`: the capture session has no audio input. `ClipSound.sessionMic`: add the default audio device as an input just before the clip starts and remove it when the clip ends.
- Clip start time: use the recording delegate callback that supplies the start presentation time (`fileOutput(_:didStartRecordingTo:startPTS:from:)`), converted to seconds. With no audio input the capture session runs on the host clock, so this is directly comparable to `HostClock.now()`. If that callback is not available in the SDK, use `HostClock.now()` in the plain `didStartRecordingTo` callback and say so in the event detail.
- Photos: HEIC to `photos/photo-<n>.heic`. When `quietShutter` is true and `photoOutput.isShutterSoundSuppressionSupported`, set `isShutterSoundSuppressionEnabled` on the settings.
- Clips: `clips/clip-<n>.mov`.
- Events, with these exact kinds: `camera-open`, `camera-ready`, `camera-close`, `photo` (detail `quiet` or `normal`, plus `suppression-unsupported` when it was asked for and not available), `clip-start` (detail: the `ClipSound` raw value), `clip-stop`, `camera-interrupted` (detail: the reason's name), `camera-interruption-ended`, `camera-runtime-error` (detail: the error).

- [x] **Step 2: Implement `ClipMuxer.swift`**

Build an `AVMutableComposition` with the clip's video track (keeping its preferred transform) and the session audio's track over `[audioStartSeconds, audioStartSeconds + durationSeconds]`; export with `AVAssetExportSession` and the preset `AVAssetExportPresetHighestQuality` to a `.mov` at `output`.

- [x] **Step 3: Add the camera controls to `AudioTestView.swift`**

The camera controls are enabled only while a run is going, and the camera is opened with the run's log (`camera.open(log: audio.log!)`). A "Camera" toggle (open and close), a small live preview, a "Quiet shutter" toggle, a "Clip sound" picker over `ClipSound.allCases`, a Photo button, and a Clip button that becomes "Stop clip". On `onClipFinished` with `.muxAfter`: read the run's `buffers.jsonl`, compute `AudioPosition.seconds(atHost: clipStart, …)`, and if it is not nil, mux to `clips/clip-<n>-muxed.mov` and record `clip-muxed` (detail `audio-start=<seconds to three places>`); if it is nil, record `clip-mux-skipped` (detail `no-audio-at-clip-start`).

- [ ] **Step 4: [Mac] Build and install**

Run: `tools/mac-build.sh && tools/mac-install.sh iphone`
Expected: `RESULT: OK` then `RESULT: INSTALLED on …`.

- [ ] **Step 5: [Owner] Check each control once**

Label R4: Start, Camera on, take two photos (one quiet, one not), record a 10-second clip with "mux" while clapping three times, record another with "session-mic", Stop.
Expected: the report lists `photo`, `clip-start mux`, `clip-muxed`, `clip-start session-mic` and `clip-stop` events. In the Files app, under Spike, the run folder holds two photos, `clip-1.mov`, `clip-1-muxed.mov` and `clip-2.mov`, and all three clips play.

- [x] **Step 6: Commit**

```bash
git add spike/App
git commit -m "feat(spike): photos, clips and two ways of giving a clip sound"
```

---

### Task 7: Stylus probe

**Files:**
- Create: `spike/App/StylusProbeView.swift`
- Modify: `spike/App/SpikeApp.swift` (second tab shows `StylusProbeView`)

**Interfaces:**
- Consumes: `RunStore.create`, `RunStore.deviceLine` (Task 4).
- Produces: a run folder labelled `S1` whose `report.txt` has exactly these lines, in this order:

```
STYLUS REPORT
device: <device line>
pencil touches: <n>
finger touches: <n>
max simultaneous touches while a pencil touch was down: <n>
max simultaneous finger touches: <n>
force varied: YES|NO
stylus draws in pencil-only mode: YES|NO|NOT ANSWERED
resting palm leaves marks in any-input mode: YES|NO|NOT ANSWERED
```

- [x] **Step 1: Implement `StylusProbeView.swift`**

Top half: a `UIView` (wrapped for SwiftUI) with `isMultipleTouchEnabled = true` that overrides the four touch methods and counts touches that begin by `UITouch.type` (`.pencil` as pencil; `.direct` as finger), tracks the largest number of touches down at once (overall, and while a pencil touch is down), and notes whether `force` took more than one distinct value. A live readout shows the counts.

Bottom half: a `PKCanvasView` with a segmented control switching `drawingPolicy` between `.pencilOnly` and `.anyInput`, a Clear button, and two three-way pickers (Yes, No, Not answered) for the last two report lines.

A "Save stylus report" button creates the `S1` run folder and writes the report.

- [ ] **Step 2: [Mac] Build and install on the iPad**

Run: `tools/mac-build.sh && tools/mac-install.sh ipad`
Expected: `RESULT: OK` then `RESULT: INSTALLED on …`.

- [ ] **Step 3: [Owner] Check the probe responds**

On the iPad, Stylus tab: touch the top half with a finger, then with the stylus.
Expected: the counts change, and drawing appears in the bottom half in at least one of the two modes.

- [x] **Step 4: Commit**

```bash
git add spike/App
git commit -m "feat(spike): stylus touch-type probe for the iPad"
```

---

### Task 8: Test protocol and results

**Files:**
- Create: `docs/spike/test-protocol.md`, `tools/mac-fetch-results.sh`, `docs/spike/results/<hardware model>/<run folder>/report.txt` (one per run)

**Interfaces:**
- Consumes: the installed app from Tasks 4 to 7.
- Produces: committed reports for every run below, which Task 9 reads.

- [x] **Step 1: Write `docs/spike/test-protocol.md`**

Plain language, one numbered action per line, for the owner. Before the runs: charge above 50 percent, turn off Low Power Mode, and do all runs within seven days of the install. The runs:

| Run | Device | What the owner does | What counts as a pass |
|---|---|---|---|
| R1 | iPhone | Start; phone on the table, screen on, 3 minutes; Stop | continuous YES |
| R2 | iPhone | Start; lock for 5 minutes; unlock; Stop | continuous YES |
| R3 | iPhone | Start; go to the home screen; use Safari for 2 minutes; return; Stop | continuous YES |
| R4 | iPhone | Start; Camera on; 5 photos 10 seconds apart with Quiet shutter off, then 5 with it on; Stop. Afterwards listen to the audio for shutter sounds. | continuous YES; note whether the shutter is heard in each half |
| R5 | iPhone | Start; Camera on; Clip sound "mux"; two 20-second clips, clapping three times in each; Stop. Watch both muxed clips. | continuous YES; claps match the picture in both |
| R6 | iPhone | As R5 with Clip sound "session-mic" | continuous YES; both clips have sound |
| R7 | iPhone | Start; Camera on; start a clip; after 10 seconds go to the home screen; after 30 seconds return; Stop | continuous YES; the clip plays up to the moment of leaving; a `camera-interrupted` event is listed |
| R8 | iPhone | Start; have someone call: decline once, then answer once for 20 seconds and hang up; do not touch the app; wait 30 seconds; Stop | recording resumes by itself (`engine-restart-ok`); gaps only around the answered call |
| R9 | iPhone | Start; at 30 seconds connect Bluetooth headphones; at 60 seconds disconnect them; Stop at 90 seconds | continuous YES |
| R10 | iPhone | Start; after 60 seconds swipe the app away in the app switcher; reopen it | a report marked UNFINISHED whose `recovered-at-launch` event shows `readable-seconds` of 55 or more |
| R11 | iPhone | Note the battery percentage; Start; lock for 60 minutes off the charger; unlock; Stop; note the battery percentage again | continuous YES; both percentages written down |
| R12 | iPad | As R2 | continuous YES |
| S1 | iPad | Stylus tab: write a sentence with the stylus with your hand resting on the screen, in each drawing mode; answer the two questions; Save stylus report | a report is saved |

The document ends with a short table for the owner to fill in: the battery percentages for R11, whether the shutter was heard in each half of R4, and whether the claps matched in R5 and the clips had sound in R6.

- [x] **Step 2: Write `tools/mac-fetch-results.sh`**

Takes `iphone` or `ipad`. Copies the app's `Documents/runs` folder from the device into `build/fetched/<hardware model>/` (which git ignores), using `xcrun devicectl device copy from` with the app's data container. Then copies each run's `report.txt`, and nothing else, into `docs/spike/results/<hardware model>/<run folder>/report.txt`. Confirm the exact flags with `xcrun devicectl help device copy from` before writing them. Last line: `RESULT: FETCHED <n> reports`. The audio and clips in `build/fetched/` are where the owner listens and watches for R4, R5 and R6. If the copy cannot be made to work, the fallback is the owner sharing each report from the Reports tab to the Mac by AirDrop and saving it at the same path.

- [ ] **Step 3: [Owner] Carry out every run in the protocol and fill in its table**

- [ ] **Step 4: [Mac] Fetch the reports**

Run: `tools/mac-fetch-results.sh iphone`, then `tools/mac-fetch-results.sh ipad`
Expected: `RESULT: FETCHED 11 reports` or more for the iPhone and `2` or more for the iPad. `git status` lists only `report.txt` files under `docs/spike/results/`.

- [ ] **Step 5: Check the reports are complete and clean**

Run: `grep -L "VERDICT\|STYLUS REPORT" -r docs/spike/results; grep -rn "device:" docs/spike/results | sort -u`
Expected: the first command prints nothing; every `device:` line shows a hardware model and OS version and no personal name.

- [ ] **Step 6: Commit**

```bash
git add docs/spike/test-protocol.md tools/mac-fetch-results.sh docs/spike/results
git commit -m "docs(spike): test protocol and device results"
```

---

### Task 9: Decision records, and removing the spike

**Files:**
- Create: `docs/adr/0001-audio-pipeline.md`, `docs/adr/0002-stylus-input.md`
- Modify: `docs/superpowers/specs/2026-11-23-field-notebook-recorder-design.md` (stage 0 line in section 7)
- Delete: `spike/`

**Interfaces:**
- Consumes: the reports and the owner's filled-in table from Task 8.
- Produces: the two decision records that the stage 1 and stage 3 plans are written from.

- [ ] **Step 1: Write `docs/adr/0001-audio-pipeline.md` from the results**

Context: what was tested and on which hardware model and OS version, with the path of every report cited. Decision, applying these rules to the reports:

| Question | Rule |
|---|---|
| Is an audio engine that owns the microphone, beside a video-only capture session, good enough for session audio? | Yes if R1, R2, R3, R4, R7, R9, R11 and R12 are continuous YES and R8 resumed by itself. Otherwise the record's status is "Rejected", it says which runs failed, and the work stops here for the owner to decide on a second spike. |
| How does a clip get its sound? | "Added after the clip from the session audio" if R5 passed. Otherwise "from the capture session's own microphone input" if R6 passed. If neither passed, as for the row above. |
| What file is written while recording? | The format used in the spike, if R10 showed 55 or more readable seconds. Otherwise "a new file every 60 seconds", stated as a requirement on stage 1. |
| Can the shutter be silenced? | Whatever R4 and the owner's table show, including whether suppression was reported as unsupported. |

Consequences: the audio session category, mode and options used; the largest gap seen in any passing run; the battery drop per hour from R11; and anything the reports show that the spec did not expect.

- [ ] **Step 2: Write `docs/adr/0002-stylus-input.md` from the S1 report**

Decision, by these rules: if `pencil touches` is above zero, the stylus is treated as a pencil, so ink uses pencil-only drawing with finger scrolling. Otherwise ink accepts any touch, with an explicit switch between drawing and scrolling. If the report says a resting palm leaves marks, the record says plainly that comfortable handwriting needs an Apple Pencil the iPad mini supports (2nd generation or USB-C), and that this is the owner's choice to make.

- [ ] **Step 3: Update the spec**

In section 7 of the spec, add to the end of the stage 0 item: `Completed <date>; findings in docs/adr/0001-audio-pipeline.md and docs/adr/0002-stylus-input.md.`

- [ ] **Step 4: Delete the spike**

Run: `git rm -r spike && rm -rf spike build`
Expected: `ls spike` reports no such directory. `tools/`, `docs/spike/` and `.gitignore` stay as they are.

- [ ] **Step 5: Commit**

```bash
git add docs/adr docs/superpowers/specs
git commit -m "docs: audio pipeline and stylus decisions from the stage 0 spike; remove spike code"
```

- [ ] **Step 6: [Owner] Remove the Spike app from both devices**

Free accounts allow only a few installed test apps at once, and stage 1 needs the room.
