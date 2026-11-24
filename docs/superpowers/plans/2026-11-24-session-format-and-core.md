# Session Format and Core Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the tested, device-independent heart of the recorder: the session folder format (written down as a JSON Schema with a worked example) and the core library that keeps a session's timeline and writes its folder.

**Architecture:** A pure-Swift package, `Core/` (module `ScrivnerCore`), with no Apple-only frameworks, so every test runs on Linux and on the Mac. Small value types (instants, offsets, ids), a deterministic JSON writer so `session.json` is byte-for-byte the same on every platform, a manifest model, a timeline that turns "this happened at this moment" into placed items, and a store that writes and reads the folder. The format's single definition is `format/field-session.v1.schema.json`; a Node script checks the committed example against it and checks that deliberately broken samples are rejected.

**Tech Stack:** Swift 6.4 (language mode 6), XCTest, Foundation only; CryptoKit on Apple platforms for hashing with a pure-Swift SHA-256 elsewhere; Node 22 with Ajv for schema checks; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-23-field-notebook-recorder-design.md` (section 6, the session folder; section 7, how it is built).

**Where this sits.** Second plan. It does not depend on the stage 0 spike (`2026-11-24-stage-0-spike.md`). Not in this plan, each a later plan: the session checker that reads media tags with ExifTool and the example's real media; the iPhone app (stage 1); video (stage 2); iPad and stylus (stage 3). Making the zip for sharing is the app's job in stage 1.

## Global Constraints

- All commands run from the repository root. `swift test --package-path Core` must pass on Linux (Swift 6.4.3) and on the Mac.
- `Core/` imports Foundation only. No AVFoundation, UIKit, SwiftUI, CoreLocation or other Apple-only framework, and no package dependencies. `#if canImport(CryptoKit)` is the one permitted platform branch.
- Swift language mode 6. Tests use XCTest.
- Format rules, verbatim from spec section 6.1: ids are UUIDv7; instants are UTC, ISO 8601, with milliseconds and `Z` (for example `2026-11-23T10:42:10.120Z`); hashes are SHA-256, 64 lower-case hex characters; all paths in `session.json` are relative to the session folder and use forward slashes; no file or folder name begins with a dot.
- Folder name rule, verbatim: `<date> <start time> <title> [<4-character id>]`; Unicode NFC; the characters `< > : " / \ | ? *` and control characters become `-`; runs of spaces collapse; no trailing dots or spaces; Windows reserved names (CON, PRN, AUX, NUL, COM1-9, LPT1-9) get a `_` prefix; the whole name is at most 150 UTF-8 bytes, shortened on a whole character with `…`.
- `session.json` has `"format": "ao-field-session"` and `"version": 1`.
- `offsetMs` comes from the monotonic clock, never from subtracting wall-clock times (spec section 6.2).
- The repository is public: no personal names, emails or device identifiers in code, tests, fixtures or examples. Example data uses the participant code `P-014` and invented notes only.
- Work on a branch named `foundations`, cut from `stage-0-spike`. Do not commit to `main` directly.

## Review Focus

Inputs the spec implies that are most likely to bite, each pinned by a test in the task named:

1. **The device clock is corrected, or the time zone changes, mid-session.** Positions on the audio must not move. `testWallClockJumpDoesNotMoveOffsets` and `testTimeZoneChangeIsKeptPerItem` (Task 7).
2. **A title that is hostile to file systems:** slashes, a reserved Windows name, only dots, emoji, or 300 characters. `NamingTests` (Task 3).
3. **A session cut off by a crash:** an open span and an open clip in `session.json`. `testCrashRecoveryClosesTheOpenSpanAndClip` (Task 7) and `testLoadedOpenSessionNeedsRecovery` (Task 7).
4. **A `session.json` that is damaged or hand-edited:** wrong types, unknown keys, an item pointing at a span that does not exist. `testDecodeReportsThePathOfTheProblem` (Task 6) and `ManifestProblemsTests` (Task 8).
5. **Text that breaks naive JSON or Markdown:** quotes, backslashes, newlines, tabs, non-Latin scripts in a note or a title. `testStringsAreEscaped` (Task 5) and `testNotesKeepOtherScriptsAndEscapeNothing` (Task 9).

---

## File Structure

```
Core/
  Package.swift
  Sources/ScrivnerCore/
    Instant.swift          Instant (UTC milliseconds) and UTCOffset
    Ids.swift              UUIDv7, IdSource, RandomIdSource, SeededIdSource
    Naming.swift           file-system-safe names and the session folder name
    SHA256Hex.swift        hashing data and files
    JSONValue.swift        an ordered JSON value with a deterministic writer and a parser
    Manifest.swift         the session.json model
    ManifestCoding.swift   Manifest <-> JSONValue, with path-carrying errors
    ManifestProblems.swift cross-reference checks on a decoded manifest
    SessionTimeline.swift  span bookkeeping and placing items on the audio
    NotesMarkdown.swift    notes.md
    SessionStore.swift     the folder on disk: create, save, load, finalize, rename
    ExampleSession.swift   the scripted example session (used by tests and to regenerate format/examples)
  Tests/ScrivnerCoreTests/  one test file per source file
format/
  field-session.v1.schema.json
  README.md
  examples/2026-11-23 1042 Market visit [<id4>]/   session.json, notes.md, placeholder media
  invalid/*.json           samples the schema must reject
  package.json, validate.mjs
.github/workflows/core.yml
docs/adr/0003-session-folder-format.md
```

---

### Task 1: Package, instants and offsets

**Files:**
- Create: `Core/Package.swift`, `Core/Sources/ScrivnerCore/Instant.swift`
- Test: `Core/Tests/ScrivnerCoreTests/InstantTests.swift`

**Interfaces:**
- Produces:

```swift
public struct Instant: Hashable, Comparable, Sendable {
    public let millisecondsSince1970: Int64
    public init(millisecondsSince1970: Int64)
    public init(date: Date)                 // rounded to the nearest millisecond
    public init?(iso: String)               // accepts exactly "YYYY-MM-DDTHH:MM:SS.mmmZ"
    public var iso: String
    public func adding(milliseconds: Int64) -> Instant
}
public struct UTCOffset: Hashable, Sendable {
    public let seconds: Int                 // east of UTC
    public init(seconds: Int)
    public init?(string: String)            // "+00:00", "-05:30"
    public var string: String
}
public struct LocalClock: Equatable, Sendable {   // an instant seen through an offset
    public let year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
    public init(_ instant: Instant, offset: UTCOffset)
}
```

- [ ] **Step 1: Write `Core/Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScrivnerCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [.library(name: "ScrivnerCore", targets: ["ScrivnerCore"])],
    targets: [
        .target(name: "ScrivnerCore"),
        .testTarget(name: "ScrivnerCoreTests", dependencies: ["ScrivnerCore"]),
    ],
    swiftLanguageModes: [.v6]
)
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class InstantTests: XCTestCase {
    func testIsoRoundTripWithMilliseconds() {
        let i = Instant(iso: "2026-11-23T10:42:10.120Z")!
        XCTAssertEqual(i.millisecondsSince1970, 1_795_430_530_120)
        XCTAssertEqual(i.iso, "2026-11-23T10:42:10.120Z")
    }
    func testIsoRejectsOtherShapes() {
        for bad in ["2026-11-23T10:42:10Z", "2026-11-23T10:42:10.120+00:00", "2026-11-23 10:42:10.120Z",
                    "2026-13-01T00:00:00.000Z", "2026-02-30T00:00:00.000Z", ""] {
            XCTAssertNil(Instant(iso: bad), bad)
        }
    }
    func testEpochAndLeapDay() {
        XCTAssertEqual(Instant(millisecondsSince1970: 0).iso, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(Instant(iso: "2028-02-29T23:59:59.999Z")!.adding(milliseconds: 1).iso, "2028-03-01T00:00:00.000Z")
    }
    func testDateIsRoundedToMilliseconds() {
        XCTAssertEqual(Instant(date: Date(timeIntervalSince1970: 1.2346)).millisecondsSince1970, 1235)
    }
    func testOffsetStrings() {
        XCTAssertEqual(UTCOffset(seconds: 0).string, "+00:00")
        XCTAssertEqual(UTCOffset(seconds: -19_800).string, "-05:30")
        XCTAssertEqual(UTCOffset(string: "+05:45")?.seconds, 20_700)
        for bad in ["Z", "+5:45", "+05:60", "05:45", "+25:00"] { XCTAssertNil(UTCOffset(string: bad), bad) }
    }
    func testLocalClockAppliesTheOffset() {
        let c = LocalClock(Instant(iso: "2026-11-23T23:30:00.000Z")!, offset: UTCOffset(seconds: 3600))
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute, c.second], [2026, 11, 24, 0, 30, 0])
    }
}
```

- [ ] **Step 3: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `Instant`, `UTCOffset` and `LocalClock` as undefined.

- [ ] **Step 4: Implement `Instant.swift`**

Do the calendar arithmetic by hand (days-from-civil), not with `Calendar` or `DateFormatter`, so results cannot depend on the machine's locale or time zone. `init?(iso:)` checks the shape character by character and that the date exists. Offsets are valid from -18:00 to +18:00 with minutes 00 to 59.

- [ ] **Step 5: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Core && git commit -m "feat(core): package with instants and UTC offsets"
```

---

### Task 2: Ids

**Files:**
- Create: `Core/Sources/ScrivnerCore/Ids.swift`
- Test: `Core/Tests/ScrivnerCoreTests/IdsTests.swift`

**Interfaces:**
- Consumes: `Instant` (Task 1).
- Produces:

```swift
public enum UUIDv7 {
    /// randomA uses its low 12 bits; randomB its low 62 bits.
    public static func make(at instant: Instant, randomA: UInt16, randomB: UInt64) -> String
    public static func isValid(_ string: String) -> Bool      // lower-case, hyphenated, version 7, variant 10
    public static func shortId(_ id: String) -> String        // the last 4 characters
}
public protocol IdSource: Sendable {
    mutating func next(at instant: Instant) -> String
}
public struct RandomIdSource: IdSource { public init() }
public struct SeededIdSource: IdSource { public init(seed: UInt64) }   // SplitMix64; same seed, same ids
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class IdsTests: XCTestCase {
    func testLayout() {
        let id = UUIDv7.make(at: Instant(millisecondsSince1970: 0x0123_4567_89AB), randomA: 0xCDE, randomB: 0x0123_4567_89AB_CDEF)
        XCTAssertEqual(id, "01234567-89ab-7cde-8123-456789abcdef")
        XCTAssertTrue(UUIDv7.isValid(id))
        XCTAssertEqual(UUIDv7.shortId(id), "cdef")
    }
    func testExtraRandomBitsAreMasked() {
        let id = UUIDv7.make(at: Instant(millisecondsSince1970: 1), randomA: 0xFFFF, randomB: .max)
        XCTAssertEqual(id, "00000000-0001-7fff-bfff-ffffffffffff")
    }
    func testIsValidRejects() {
        for bad in ["01234567-89AB-7CDE-8123-456789ABCDEF", "01234567-89ab-4cde-8123-456789abcdef",
                    "01234567-89ab-7cde-0123-456789abcdef", "0123456789ab7cde8123456789abcdef", ""] {
            XCTAssertFalse(UUIDv7.isValid(bad), bad)
        }
    }
    func testSeededSourceRepeatsAndRandomSourceIsValid() {
        var a = SeededIdSource(seed: 1), b = SeededIdSource(seed: 1), r = RandomIdSource()
        let t = Instant(millisecondsSince1970: 1_795_430_530_120)
        let first = a.next(at: t)
        XCTAssertEqual(first, b.next(at: t))
        XCTAssertNotEqual(first, a.next(at: t))
        XCTAssertTrue(UUIDv7.isValid(first))
        XCTAssertTrue(UUIDv7.isValid(r.next(at: t)))
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `UUIDv7`, `SeededIdSource` and `RandomIdSource` as undefined.

- [ ] **Step 3: Implement `Ids.swift`**

Layout: 48 bits of Unix milliseconds, 4 bits `0111`, 12 bits `randomA`, 2 bits `10`, 62 bits `randomB`. `SeededIdSource` advances a SplitMix64 state twice per id.

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): UUIDv7 ids with random and seeded sources"
```

---

### Task 3: Names

**Files:**
- Create: `Core/Sources/ScrivnerCore/Naming.swift`
- Test: `Core/Tests/ScrivnerCoreTests/NamingTests.swift`

**Interfaces:**
- Consumes: `Instant`, `UTCOffset`, `LocalClock` (Task 1); `UUIDv7.shortId` (Task 2).
- Produces:

```swift
public enum Naming {
    public static let maxBytes = 150
    public static func sanitize(_ text: String) -> String      // may return ""
    public static func sessionFolderName(createdAt: Instant, utcOffset: UTCOffset, title: String, sessionId: String) -> String
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class NamingTests: XCTestCase {
    let at = Instant(iso: "2026-11-23T10:42:10.120Z")!
    let id = "01234567-89ab-7cde-8123-456789abcdef"

    func testSanitizeReplacesForbiddenCharacters() {
        XCTAssertEqual(Naming.sanitize("a<b>c:d\"e/f\\g|h?i*j"), "a-b-c-d-e-f-g-h-i-j")
        XCTAssertEqual(Naming.sanitize("bell\u{07}tab\there"), "bell-tab-here")
    }
    func testSanitizeTidiesSpacesAndDots() {
        XCTAssertEqual(Naming.sanitize("  many   spaces  "), "many spaces")
        XCTAssertEqual(Naming.sanitize("name... "), "name")
        XCTAssertEqual(Naming.sanitize("...hidden"), "hidden")
        XCTAssertEqual(Naming.sanitize(" . . "), "")
    }
    func testSanitizeHandlesReservedNamesAndNFC() {
        XCTAssertEqual(Naming.sanitize("CON"), "_CON")
        XCTAssertEqual(Naming.sanitize("com1.txt"), "_com1.txt")
        XCTAssertEqual(Naming.sanitize("Console"), "Console")
        XCTAssertEqual(Naming.sanitize("e\u{301}").unicodeScalars.count, 1)
        XCTAssertEqual(Naming.sanitize("Рынок 市場 سوق"), "Рынок 市場 سوق")
    }
    func testFolderName() {
        XCTAssertEqual(Naming.sessionFolderName(createdAt: at, utcOffset: UTCOffset(seconds: 0), title: "Market visit", sessionId: id),
                       "2026-11-23 1042 Market visit [cdef]")
        XCTAssertEqual(Naming.sessionFolderName(createdAt: at, utcOffset: UTCOffset(seconds: -5 * 3600), title: "A/B", sessionId: id),
                       "2026-11-23 0542 A-B [cdef]")
        XCTAssertEqual(Naming.sessionFolderName(createdAt: at, utcOffset: UTCOffset(seconds: 0), title: " .. ", sessionId: id),
                       "2026-11-23 1042 [cdef]")
    }
    func testLongTitlesAreCutOnAWholeCharacter() {
        let long = String(repeating: "é👩‍👩‍👧", count: 60)
        let name = Naming.sessionFolderName(createdAt: at, utcOffset: UTCOffset(seconds: 0), title: long, sessionId: id)
        XCTAssertLessThanOrEqual(name.utf8.count, 150)
        XCTAssertTrue(name.hasPrefix("2026-11-23 1042 é👩‍👩‍👧"))
        XCTAssertTrue(name.hasSuffix("… [cdef]"))
        XCTAssertFalse(name.contains("\u{FFFD}"))
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `Naming` as undefined.

- [ ] **Step 3: Implement `Naming.swift`**

`sanitize`, in this order: NFC (`precomposedStringWithCanonicalMapping`); replace each of `< > : " / \ | ? *` and each scalar in the Unicode general categories Cc with `-`; collapse runs of whitespace to one space; trim leading and trailing spaces and dots; if the name without its extension, upper-cased, is a reserved Windows name, prefix `_`.

`sessionFolderName`: `"<yyyy-MM-dd> <HHmm>"` from `LocalClock(createdAt, offset:)`, then a space and the sanitized title when it is not empty, then `" [<shortId>]"`. If the result is over 150 UTF-8 bytes, drop whole `Character`s from the end of the title until the name with `…` appended to the title fits.

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 15 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): file-system-safe names and the session folder name"
```

---

### Task 4: Hashing

**Files:**
- Create: `Core/Sources/ScrivnerCore/SHA256Hex.swift`
- Test: `Core/Tests/ScrivnerCoreTests/SHA256HexTests.swift`

**Interfaces:**
- Produces:

```swift
public enum SHA256Hex {
    public static func of(_ data: Data) -> String
    public static func ofFile(at url: URL) throws -> String     // streamed, 1 MiB at a time
    public static func isValid(_ string: String) -> Bool        // 64 lower-case hex characters
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class SHA256HexTests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(SHA256Hex.of(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256Hex.of(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256Hex.of(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(SHA256Hex.of(Data(repeating: 0x61, count: 1_000_000)),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
    func testFileHashMatchesDataHashAcrossChunks() throws {
        let data = Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sha-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try SHA256Hex.ofFile(at: url), SHA256Hex.of(data))
    }
    func testMissingFileThrows() {
        XCTAssertThrowsError(try SHA256Hex.ofFile(at: URL(fileURLWithPath: "/nonexistent/file.bin")))
    }
    func testIsValid() {
        XCTAssertTrue(SHA256Hex.isValid(String(repeating: "a", count: 64)))
        XCTAssertFalse(SHA256Hex.isValid(String(repeating: "A", count: 64)))
        XCTAssertFalse(SHA256Hex.isValid(String(repeating: "a", count: 63)))
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `SHA256Hex` as undefined.

- [ ] **Step 3: Implement `SHA256Hex.swift`**

One internal streaming hasher type with `update(_:)` and `finalize() -> String`, implemented twice behind `#if canImport(CryptoKit)`: CryptoKit's `SHA256` on Apple platforms, a plain FIPS 180-4 implementation elsewhere. `ofFile` reads with `FileHandle` in 1 MiB chunks.

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 19 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): SHA-256 hashing of data and files"
```

---

### Task 5: Deterministic JSON

**Files:**
- Create: `Core/Sources/ScrivnerCore/JSONValue.swift`
- Test: `Core/Tests/ScrivnerCoreTests/JSONValueTests.swift`

**Interfaces:**
- Produces:

```swift
public indirect enum JSONValue: Equatable, Sendable {
    case null, bool(Bool), int(Int), double(Double), string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])     // order is kept and written as given
    public func written() -> String                     // 2-space indent, "key": value, ends with "\n"
    public static func parse(_ text: String) throws -> JSONValue
    public subscript(key: String) -> JSONValue? { get } // first match in an object, else nil
}
public struct JSONParseError: Error, Equatable { public let message: String }
```

(`Equatable` for `.object` compares keys and values in order.)

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class JSONValueTests: XCTestCase {
    func testWrittenFormIsExact() {
        let v = JSONValue.object([
            ("format", .string("ao-field-session")), ("version", .int(1)),
            ("participants", .array([.string("P-014")])), ("empty", .array([])),
            ("gps", .object([("lat", .double(38.7223)), ("alt", .double(12))])),
            ("items", .array([.object([("sound", .bool(true)), ("note", .null)])])),
            ("bounds", .array([.double(0), .double(10.5)])),
        ])
        XCTAssertEqual(v.written(), """
        {
          "format": "ao-field-session",
          "version": 1,
          "participants": ["P-014"],
          "empty": [],
          "gps": {
            "lat": 38.7223,
            "alt": 12.0
          },
          "items": [
            {
              "sound": true,
              "note": null
            }
          ],
          "bounds": [0.0, 10.5]
        }

        """)
    }
    func testStringsAreEscaped() {
        let v = JSONValue.object([("t", .string("say \"hi\" \\ \n\t\u{01} Рынок 市場 👩‍👩‍👧"))])
        XCTAssertEqual(v.written(), "{\n  \"t\": \"say \\\"hi\\\" \\\\ \\n\\t\\u0001 Рынок 市場 👩‍👩‍👧\"\n}\n")
    }
    func testParseRoundTripKeepsOrderAndNumberKinds() throws {
        let text = "{\"b\": 1, \"a\": 1.5, \"c\": [true, null, \"x\"], \"d\": {\"z\": -3}}"
        let v = try JSONValue.parse(text)
        XCTAssertEqual(v, .object([("b", .int(1)), ("a", .double(1.5)),
                                   ("c", .array([.bool(true), .null, .string("x")])), ("d", .object([("z", .int(-3))]))]))
        XCTAssertEqual(try JSONValue.parse(v.written()), v)
        XCTAssertEqual(v["a"], .double(1.5))
        XCTAssertNil(v["missing"])
    }
    func testParseHandlesEscapesAndRejectsRubbish() throws {
        XCTAssertEqual(try JSONValue.parse("\"a\\u00e9\\n\\ud83d\\ude00\""), .string("aé\n😀"))
        for bad in ["", "{", "[1,]", "{\"a\":1,}", "{\"a\" 1}", "01", "1 2", "{\"a\":1,\"a\":2}", "nul", "\"\u{01}\""] {
            XCTAssertThrowsError(try JSONValue.parse(bad), bad)
        }
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `JSONValue` as undefined.

- [ ] **Step 3: Implement `JSONValue.swift`**

Writer rules, which the exact-text test pins: an array whose elements are all scalars is written on one line; any other array or a non-empty object is written one element per line; an empty object is `{}`; doubles are written with Swift's `"\(value)"` (so `12` is `12.0`); non-finite doubles are written as `null`; strings escape `"`, `\`, newline, carriage return, tab, and every other scalar below U+0020 as `\u00XX`, and nothing else.

Parser: a hand-written recursive-descent parser over the UTF-8 bytes, so key order is kept and a duplicate key in one object is an error. A number with no fraction or exponent that fits in `Int` is `.int`; otherwise `.double`.

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 23 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): ordered JSON with a deterministic writer and a strict parser"
```

---

### Task 6: The manifest

**Files:**
- Create: `Core/Sources/ScrivnerCore/Manifest.swift`, `Core/Sources/ScrivnerCore/ManifestCoding.swift`
- Test: `Core/Tests/ScrivnerCoreTests/ManifestCodingTests.swift`

**Interfaces:**
- Consumes: `Instant`, `UTCOffset` (Task 1); `JSONValue` (Task 5).
- Produces:

```swift
public struct GeoPoint: Equatable, Sendable { public var lat: Double, lon: Double, alt: Double?, accuracyM: Double? }
public struct DeviceInfo: Equatable, Sendable { public var model: String, os: String, app: String }
public enum SpanEnd: String, Sendable { case pause, stop, interruption, crashRecovered = "crash-recovered" }
public struct Span: Equatable, Sendable {
    public var id: String, file: String, sha256: String?
    public var startedAt: Instant, utcOffset: UTCOffset, timeZone: String
    public var durationMs: Int?, endedBy: SpanEnd?          // both nil while the span is open
}
public enum MarkerType: String, Sendable {
    case recordingStarted = "recording-started", paused, resumed, stopped, interrupted
    case locationOff = "location-off", locationOn = "location-on"
}
public enum ClipEnd: String, Sendable { case user, background, lock, interruption, stop }
public struct Placement: Equatable, Sendable {             // what every item has
    public var id: String, at: Instant, utcOffset: UTCOffset
    public var spanId: String?, offsetMs: Int?              // both nil when nothing was recording
}
public struct InkStroke: Equatable, Sendable { public var at: Instant, offsetMs: Int?, bounds: [Double] }
public enum Item: Equatable, Sendable {
    case marker(Placement, type: MarkerType, detail: String?)
    case text(Placement, text: String, modifiedAt: Instant?)
    case photo(Placement, file: String, sha256: String?, gps: GeoPoint?)
    case video(Placement, durationMs: Int?, endedBy: ClipEnd?, sound: Bool, file: String, sha256: String?, gps: GeoPoint?)
    case ink(Placement, endAt: Instant?, file: String, sha256: String?, data: String, dataSha256: String?, strokes: [InkStroke])
    public var placement: Placement { get set }
    public var kind: String { get }                         // "marker" | "text" | "photo" | "video" | "ink"
}
public struct Manifest: Equatable, Sendable {
    public static let format = "ao-field-session"
    public static let version = 1
    public var id: String, title: String
    public var createdAt: Instant, utcOffset: UTCOffset, timeZone: String
    public var participants: [String], researcher: String?
    public var device: DeviceInfo, startLocation: GeoPoint?
    public var spans: [Span], items: [Item]
}
public struct ManifestDecodeError: Error, Equatable { public let path: String; public let message: String }
public enum ManifestCoding {
    public static func json(_ manifest: Manifest) -> JSONValue
    public static func encode(_ manifest: Manifest) -> String                 // json(manifest).written()
    public static func decode(_ text: String) throws -> Manifest              // throws ManifestDecodeError or JSONParseError
}
```

All the structs above have public memberwise initialisers.

Key order in `session.json`, which the tests pin:
- top level: `format`, `version`, `id`, `title`, `createdAt`, `utcOffset`, `timeZone`, `participants`, `researcher`, `device` (`model`, `os`, `app`), `startLocation`, `spans`, `items`
- a location: `lat`, `lon`, `alt`, `accuracyM`
- a span: `id`, `file`, `sha256`, `startedAt`, `utcOffset`, `timeZone`, `durationMs`, `endedBy`
- every item starts `id`, `kind`, then `type` (markers only), `at`, `endAt` (ink only), `utcOffset`, `spanId`, `offsetMs`; then by kind: marker `detail`; text `text`, `modifiedAt`; photo `file`, `sha256`, `gps`; video `durationMs`, `endedBy`, `sound`, `file`, `sha256`, `gps`; ink `file`, `sha256`, `data`, `dataSha256`, `strokes` (each `at`, `offsetMs`, `bounds`)
- a key whose value is nil is left out, never written as `null`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class ManifestCodingTests: XCTestCase {
    static let t0 = Instant(iso: "2026-11-23T10:42:10.120Z")!
    static let zero = UTCOffset(seconds: 0)
    static func sample() -> Manifest {
        let p = Placement(id: "00000000-0000-7000-8000-000000000002", at: t0.adding(milliseconds: 65_000), utcOffset: zero,
                          spanId: "00000000-0000-7000-8000-000000000001", offsetMs: 65_000)
        return Manifest(id: "00000000-0000-7000-8000-000000000000", title: "Market visit",
                        createdAt: t0, utcOffset: zero, timeZone: "Europe/Lisbon",
                        participants: ["P-014"], researcher: nil,
                        device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                        startLocation: GeoPoint(lat: 38.7223, lon: -9.1393, alt: nil, accuracyM: 5),
                        spans: [Span(id: "00000000-0000-7000-8000-000000000001", file: "audio/audio-001.m4a", sha256: nil,
                                     startedAt: t0, utcOffset: zero, timeZone: "Europe/Lisbon", durationMs: nil, endedBy: nil)],
                        items: [.text(p, text: "P-014 has run the stall since 2009.", modifiedAt: nil)])
    }

    func testEncodedTextIsExact() {
        XCTAssertEqual(ManifestCoding.encode(Self.sample()), """
        {
          "format": "ao-field-session",
          "version": 1,
          "id": "00000000-0000-7000-8000-000000000000",
          "title": "Market visit",
          "createdAt": "2026-11-23T10:42:10.120Z",
          "utcOffset": "+00:00",
          "timeZone": "Europe/Lisbon",
          "participants": ["P-014"],
          "device": {
            "model": "iPhone18,1",
            "os": "iOS 27.1",
            "app": "0.1.0"
          },
          "startLocation": {
            "lat": 38.7223,
            "lon": -9.1393,
            "accuracyM": 5.0
          },
          "spans": [
            {
              "id": "00000000-0000-7000-8000-000000000001",
              "file": "audio/audio-001.m4a",
              "startedAt": "2026-11-23T10:42:10.120Z",
              "utcOffset": "+00:00",
              "timeZone": "Europe/Lisbon"
            }
          ],
          "items": [
            {
              "id": "00000000-0000-7000-8000-000000000002",
              "kind": "text",
              "at": "2026-11-23T10:43:15.120Z",
              "utcOffset": "+00:00",
              "spanId": "00000000-0000-7000-8000-000000000001",
              "offsetMs": 65000,
              "text": "P-014 has run the stall since 2009."
            }
          ]
        }

        """)
    }
    func testEveryKindRoundTrips() throws {
        var m = Self.sample()
        let p = m.items[0].placement
        var free = p; free.spanId = nil; free.offsetMs = nil
        let hash = String(repeating: "ab", count: 32)
        m.researcher = "R"
        m.spans[0].sha256 = hash; m.spans[0].durationMs = 551_000; m.spans[0].endedBy = .crashRecovered
        m.items = [
            .marker(p, type: .recordingStarted, detail: nil),
            .marker(free, type: .interrupted, detail: "phone call"),
            .text(p, text: "a \"quoted\"\nline", modifiedAt: p.at.adding(milliseconds: 5)),
            .photo(p, file: "photos/photo-0001.heic", sha256: hash, gps: GeoPoint(lat: 1.5, lon: -2.5, alt: 3, accuracyM: nil)),
            .video(free, durationMs: 48_000, endedBy: .user, sound: false, file: "video/clip-0001.mov", sha256: nil, gps: nil),
            .ink(p, endAt: p.at.adding(milliseconds: 900), file: "ink/ink-0001.png", sha256: hash, data: "ink/ink-0001.drawing",
                 dataSha256: hash, strokes: [InkStroke(at: p.at, offsetMs: 65_000, bounds: [0, 0, 10.5, 4])]),
        ]
        XCTAssertEqual(try ManifestCoding.decode(ManifestCoding.encode(m)), m)
    }
    func testDecodeReportsThePathOfTheProblem() {
        func failure(_ edit: (String) -> String) -> ManifestDecodeError? {
            do { _ = try ManifestCoding.decode(edit(ManifestCoding.encode(Self.sample()))); return nil }
            catch { return error as? ManifestDecodeError }
        }
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2") }?.path, "version")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"offsetMs\": 65000", with: "\"offsetMs\": 65000.5") }?.path, "items[0].offsetMs")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"kind\": \"text\"", with: "\"kind\": \"song\"") }?.path, "items[0].kind")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "10:42:10.120Z\",\n      \"utcOffset", with: "10:42:10Z\",\n      \"utcOffset") }?.path, "spans[0].startedAt")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"title\": \"Market visit\",", with: "\"title\": \"Market visit\", \"extra\": 1,") }?.path, "extra")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"model\": \"iPhone18,1\",\n", with: "") }?.path, "device.model")
        XCTAssertEqual(failure { $0.replacingOccurrences(of: "\"lat\": 38.7223", with: "\"lat\": \"north\"") }?.path, "startLocation.lat")
    }
    func testDecodeAcceptsWholeNumbersForCoordinates() throws {
        let text = ManifestCoding.encode(Self.sample()).replacingOccurrences(of: "\"accuracyM\": 5.0", with: "\"accuracyM\": 5")
        XCTAssertEqual(try ManifestCoding.decode(text).startLocation?.accuracyM, 5)
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `Manifest`, `ManifestCoding` and the model types as undefined.

- [ ] **Step 3: Implement `Manifest.swift` and `ManifestCoding.swift`**

Decoding is strict: `format` must be `ao-field-session` and `version` must be `1`; an unknown key anywhere is an error whose path is that key (with its parent path); a missing required key is an error at that key's path; a wrong type or a malformed instant, offset or enum value is an error at the value's path. Whole-number JSON values are accepted where a `Double` is expected; a fractional value is rejected where an `Int` is expected. `bounds` must have exactly four numbers. Paths look like `items[3].offsetMs`.

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 27 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): the session manifest and its strict JSON coding"
```

---

### Task 7: The timeline

**Files:**
- Create: `Core/Sources/ScrivnerCore/SessionTimeline.swift`
- Test: `Core/Tests/ScrivnerCoreTests/SessionTimelineTests.swift`

**Interfaces:**
- Consumes: `Manifest` and its parts (Task 6); `IdSource` (Task 2).
- Produces:

```swift
public struct Moment: Equatable, Sendable {
    public var host: Double          // monotonic seconds; the same clock audio is stamped on
    public var wall: Instant
    public var utcOffset: UTCOffset
    public var timeZone: String
    public init(host: Double, wall: Instant, utcOffset: UTCOffset, timeZone: String)
}
public enum TimelineError: Error, Equatable {
    case alreadyRecording, notRecording, needsRecovery, noSuchItem(String), clipAlreadyEnded(String)
}
public struct SessionTimeline: Sendable {
    public private(set) var manifest: Manifest
    public var isRecording: Bool { get }
    public var needsRecovery: Bool { get }        // true after resuming a manifest that has an open span
    public init(title: String, participants: [String], researcher: String?, device: DeviceInfo,
                startLocation: GeoPoint?, at moment: Moment, ids: any IdSource)
    public init(resuming manifest: Manifest, ids: any IdSource)

    public mutating func setTitle(_ title: String)
    public mutating func setParticipants(_ participants: [String])
    @discardableResult public mutating func startRecording(file: String, at: Moment) throws -> String        // the span id
    public mutating func endRecording(by end: SpanEnd, detail: String? = nil, audioDurationMs: Int? = nil, at: Moment) throws
    public mutating func recoverAfterCrash(spanDurationMs: Int?, at: Moment)
    @discardableResult public mutating func addText(_ text: String, at: Moment) throws -> String
    public mutating func editText(id: String, text: String, at: Moment) throws
    @discardableResult public mutating func addPhoto(file: String, gps: GeoPoint?, at: Moment) throws -> String
    @discardableResult public mutating func startClip(file: String, gps: GeoPoint?, at: Moment) throws -> String
    public mutating func endClip(id: String, by end: ClipEnd, at: Moment) throws
    public mutating func setLocation(enabled: Bool, at: Moment) throws
}
```

Behaviour the tests pin:
- The first `startRecording` adds a `recording-started` marker; later ones add `resumed`. `endRecording` adds `paused`, `stopped` or `interrupted` (with `detail`) for `.pause`, `.stop`, `.interruption`.
- An item made while recording gets the open span's id and `offsetMs = round((moment.host - spanStart.host) * 1000)`, never below 0. An item made while not recording gets neither.
- A span's `durationMs` is `audioDurationMs` when given, else `round((end.host - start.host) * 1000)`.
- A clip's `sound` is whether recording was on when it started; its `durationMs` is from the host clock between `startClip` and `endClip`.
- `recoverAfterCrash` closes the open span as `crash-recovered` with the given duration, ends any clip with no `endedBy` as `.interruption` (its `durationMs` stays nil), and adds an `interrupted` marker with detail `crash-recovered`, placed with no span.
- While `needsRecovery` is true, every mutating call except `recoverAfterCrash`, `setTitle` and `setParticipants` throws `.needsRecovery`.
- Ids come from `ids.next(at: moment.wall)`: one for the session, one per span, one per item, in the order they are made.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class SessionTimelineTests: XCTestCase {
    let zero = UTCOffset(seconds: 0)
    let t0 = Instant(iso: "2026-11-23T10:42:10.120Z")!
    func moment(_ seconds: Double, wallShiftMs: Int64 = 0, offset: UTCOffset? = nil, zone: String = "Europe/Lisbon") -> Moment {
        Moment(host: 1000 + seconds, wall: t0.adding(milliseconds: Int64(seconds * 1000) + wallShiftMs),
               utcOffset: offset ?? zero, timeZone: zone)
    }
    func newTimeline() -> SessionTimeline {
        SessionTimeline(title: "Market visit", participants: ["P-014"], researcher: nil,
                        device: DeviceInfo(model: "iPhone18,1", os: "iOS 27.1", app: "0.1.0"),
                        startLocation: nil, at: moment(0), ids: SeededIdSource(seed: 1))
    }

    func testItemsArePlacedOnTheOpenSpan() throws {
        var t = newTimeline()
        let span = try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.addText("P-014 has run the stall since 2009.", at: moment(65))
        try t.addPhoto(file: "photos/photo-0001.heic", gps: nil, at: moment(185))
        XCTAssertEqual(t.manifest.items.map(\.kind), ["marker", "text", "photo"])
        XCTAssertEqual(t.manifest.items.map(\.placement.offsetMs), [0, 65_000, 185_000])
        XCTAssertEqual(Set(t.manifest.items.map(\.placement.spanId)), [span])
        XCTAssertEqual(t.manifest.items[1].placement.at.iso, "2026-11-23T10:43:15.120Z")
        XCTAssertTrue(t.isRecording)
    }
    func testPauseResumeStopMakeSpansAndMarkers() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.endRecording(by: .pause, at: moment(551))
        try t.addText("off the record", at: moment(600))
        try t.startRecording(file: "audio/audio-002.m4a", at: moment(700))
        try t.endRecording(by: .interruption, detail: "phone call", at: moment(750))
        try t.startRecording(file: "audio/audio-003.m4a", at: moment(800))
        try t.endRecording(by: .stop, audioDurationMs: 99_950, at: moment(900))
        XCTAssertEqual(t.manifest.spans.map(\.durationMs), [551_000, 50_000, 99_950])
        XCTAssertEqual(t.manifest.spans.map(\.endedBy), [.pause, .interruption, .stop])
        let markers: [String] = t.manifest.items.compactMap { if case .marker(_, let type, _) = $0 { return type.rawValue }; return nil }
        XCTAssertEqual(markers, ["recording-started", "paused", "resumed", "interrupted", "resumed", "stopped"])
        guard case .text(let p, _, _) = t.manifest.items[2] else { return XCTFail() }
        XCTAssertNil(p.spanId); XCTAssertNil(p.offsetMs)
        guard case .marker(_, _, let detail) = t.manifest.items[4] else { return XCTFail() }
        XCTAssertEqual(detail, "phone call")
        XCTAssertFalse(t.isRecording)
    }
    func testClipLengthAndSound() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        let loud = try t.startClip(file: "video/clip-0001.mov", gps: nil, at: moment(430))
        try t.endClip(id: loud, by: .user, at: moment(478))
        try t.endRecording(by: .pause, at: moment(500))
        let quiet = try t.startClip(file: "video/clip-0002.mov", gps: nil, at: moment(510))
        try t.endClip(id: quiet, by: .background, at: moment(520))
        guard case .video(let p1, let d1, let e1, let s1, _, _, _) = t.manifest.items[1],
              case .video(let p2, let d2, let e2, let s2, _, _, _) = t.manifest.items[3] else { return XCTFail() }
        XCTAssertEqual([p1.offsetMs, d1], [430_000, 48_000]); XCTAssertEqual(e1, .user); XCTAssertTrue(s1)
        XCTAssertNil(p2.spanId); XCTAssertEqual(d2, 10_000); XCTAssertEqual(e2, .background); XCTAssertFalse(s2)
        XCTAssertThrowsError(try t.endClip(id: loud, by: .user, at: moment(530))) { XCTAssertEqual($0 as? TimelineError, .clipAlreadyEnded(loud)) }
        XCTAssertThrowsError(try t.endClip(id: "nope", by: .user, at: moment(530))) { XCTAssertEqual($0 as? TimelineError, .noSuchItem("nope")) }
    }
    func testWallClockJumpDoesNotMoveOffsets() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.addText("before", at: moment(60))
        try t.addText("after the clock went back an hour", at: moment(120, wallShiftMs: -3_600_000))
        try t.endRecording(by: .stop, at: moment(180, wallShiftMs: -3_600_000))
        XCTAssertEqual(t.manifest.items.map(\.placement.offsetMs), [0, 60_000, 120_000, 180_000])
        XCTAssertEqual(t.manifest.spans[0].durationMs, 180_000)
        XCTAssertEqual(t.manifest.items[2].placement.at.iso, "2026-11-23T09:44:10.120Z")
    }
    func testTimeZoneChangeIsKeptPerItem() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.addText("landed", at: moment(60, offset: UTCOffset(seconds: 3600), zone: "Europe/Madrid"))
        XCTAssertEqual(t.manifest.items.map(\.placement.utcOffset.string), ["+00:00", "+01:00"])
        XCTAssertEqual(t.manifest.spans[0].timeZone, "Europe/Lisbon")
        XCTAssertEqual(t.manifest.items[1].placement.offsetMs, 60_000)
    }
    func testEditKeepsTheOriginalTime() throws {
        var t = newTimeline()
        let id = try t.addText("first", at: moment(10))
        try t.editText(id: id, text: "first, corrected", at: moment(90))
        guard case .text(let p, let text, let modified) = t.manifest.items[0] else { return XCTFail() }
        XCTAssertEqual(text, "first, corrected")
        XCTAssertEqual(p.at, t0.adding(milliseconds: 10_000)); XCTAssertEqual(modified, t0.adding(milliseconds: 90_000))
    }
    func testLocationMarkersAndRecordingErrors() throws {
        var t = newTimeline()
        try t.setLocation(enabled: false, at: moment(5))
        try t.setLocation(enabled: true, at: moment(6))
        let markers: [String] = t.manifest.items.compactMap { if case .marker(_, let type, _) = $0 { return type.rawValue }; return nil }
        XCTAssertEqual(markers, ["location-off", "location-on"])
        XCTAssertThrowsError(try t.endRecording(by: .stop, at: moment(7))) { XCTAssertEqual($0 as? TimelineError, .notRecording) }
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(8))
        XCTAssertThrowsError(try t.startRecording(file: "audio/audio-002.m4a", at: moment(9))) { XCTAssertEqual($0 as? TimelineError, .alreadyRecording) }
    }
    func testCrashRecoveryClosesTheOpenSpanAndClip() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.startClip(file: "video/clip-0001.mov", gps: nil, at: moment(30))
        var back = SessionTimeline(resuming: t.manifest, ids: SeededIdSource(seed: 2))
        XCTAssertTrue(back.needsRecovery)
        XCTAssertThrowsError(try back.addText("x", at: moment(500))) { XCTAssertEqual($0 as? TimelineError, .needsRecovery) }
        back.recoverAfterCrash(spanDurationMs: 42_000, at: moment(500))
        XCTAssertFalse(back.needsRecovery); XCTAssertFalse(back.isRecording)
        XCTAssertEqual(back.manifest.spans[0].durationMs, 42_000); XCTAssertEqual(back.manifest.spans[0].endedBy, .crashRecovered)
        guard case .video(_, let d, let e, _, _, _, _) = back.manifest.items[1],
              case .marker(let p, let type, let detail) = back.manifest.items[2] else { return XCTFail() }
        XCTAssertNil(d); XCTAssertEqual(e, .interruption)
        XCTAssertEqual(type, .interrupted); XCTAssertEqual(detail, "crash-recovered"); XCTAssertNil(p.spanId)
        try back.startRecording(file: "audio/audio-002.m4a", at: moment(510))
        XCTAssertEqual(back.manifest.spans.count, 2)
    }
    func testLoadedOpenSessionNeedsRecovery() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.endRecording(by: .stop, at: moment(10))
        XCTAssertFalse(SessionTimeline(resuming: t.manifest, ids: SeededIdSource(seed: 2)).needsRecovery)
    }
    func testIdsAreValidAndUnique() throws {
        var t = newTimeline()
        try t.startRecording(file: "audio/audio-001.m4a", at: moment(0))
        try t.addText("a", at: moment(1)); try t.addText("b", at: moment(1))
        let ids = [t.manifest.id] + t.manifest.spans.map(\.id) + t.manifest.items.map(\.placement.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy(UUIDv7.isValid))
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `SessionTimeline`, `Moment` and `TimelineError` as undefined.

- [ ] **Step 3: Implement `SessionTimeline.swift`**

The timeline holds the manifest, the id source, and the host time at which the open span started (nil when not recording). `init(resuming:)` sets `needsRecovery` when any span has no `endedBy`.

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 37 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): session timeline with span bookkeeping and crash recovery"
```

---

### Task 8: Checking a manifest for inconsistencies

**Files:**
- Create: `Core/Sources/ScrivnerCore/ManifestProblems.swift`
- Test: `Core/Tests/ScrivnerCoreTests/ManifestProblemsTests.swift`

**Interfaces:**
- Consumes: `Manifest` (Task 6), `UUIDv7.isValid` (Task 2), `SHA256Hex.isValid` (Task 4).
- Produces:

```swift
public struct ManifestProblem: Equatable, Sendable { public let path: String; public let message: String }
extension Manifest {
    /// Empty when the manifest is consistent. `finished` also requires every span closed and every file hashed.
    public func problems(finished: Bool) -> [ManifestProblem]
}
```

Rules, each reported at the path shown:
1. `id`, every `spans[i].id` and `items[i].id` is a valid UUIDv7, and all are different from each other.
2. Every `file` and `data` path is relative, uses `/`, has no empty, `.` or `..` segment, no segment starting with a dot, and no path is used twice.
3. An item has `spanId` and `offsetMs` together or not at all; `spanId` names an existing span; `offsetMs` is at least 0 and, when that span has a `durationMs`, at most that duration.
4. A span has `durationMs` and `endedBy` together or not at all; `durationMs` is at least 0. At most one span is open, and it is the last.
5. Every `sha256` and `dataSha256` present is 64 lower-case hex characters.
6. `lat` is within -90...90 and `lon` within -180...180.
7. With `finished: true`: no span is open, and every span, photo, video and ink item has its hashes.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class ManifestProblemsTests: XCTestCase {
    func base() -> Manifest { ManifestCodingTests.sample() }
    func paths(_ m: Manifest, finished: Bool = false) -> [String] { m.problems(finished: finished).map(\.path) }

    func testConsistentManifestHasNoProblems() { XCTAssertEqual(paths(base()), []) }
    func testIds() {
        var m = base(); m.items[0].placement.id = m.spans[0].id
        XCTAssertEqual(paths(m), ["items[0].id"])
        m = base(); m.spans[0].id = "not-an-id"; m.items[0].placement.spanId = "not-an-id"
        XCTAssertEqual(paths(m), ["spans[0].id"])
    }
    func testPaths() {
        for bad in ["/abs/a.m4a", "audio\\a.m4a", "audio/../a.m4a", "audio//a.m4a", ".hidden/a.m4a", "audio/.a.m4a", ""] {
            var m = base(); m.spans[0].file = bad
            XCTAssertEqual(paths(m), ["spans[0].file"], bad)
        }
        var m = base()
        m.items.append(.photo(m.items[0].placement, file: "audio/audio-001.m4a", sha256: nil, gps: nil))
        m.items[1].placement.id = "00000000-0000-7000-8000-000000000003"
        XCTAssertEqual(paths(m), ["items[1].file"])
    }
    func testPlacement() {
        var m = base(); m.items[0].placement.offsetMs = nil
        XCTAssertEqual(paths(m), ["items[0].spanId"])
        m = base(); m.items[0].placement.spanId = "00000000-0000-7000-8000-00000000000f"
        XCTAssertEqual(paths(m), ["items[0].spanId"])
        m = base(); m.items[0].placement.offsetMs = -1
        XCTAssertEqual(paths(m), ["items[0].offsetMs"])
        m = base(); m.spans[0].durationMs = 60_000; m.spans[0].endedBy = .stop
        XCTAssertEqual(paths(m), ["items[0].offsetMs"])
    }
    func testSpans() {
        var m = base(); m.spans[0].durationMs = 600_000
        XCTAssertEqual(paths(m), ["spans[0].endedBy"])
        m = base(); m.spans.append(m.spans[0]); m.spans[1].id = "00000000-0000-7000-8000-000000000004"; m.spans[1].file = "audio/audio-002.m4a"
        XCTAssertEqual(paths(m), ["spans[0].endedBy"])
    }
    func testHashesAndCoordinates() {
        var m = base(); m.spans[0].sha256 = "ABC"
        XCTAssertEqual(paths(m), ["spans[0].sha256"])
        m = base(); m.startLocation = GeoPoint(lat: 91, lon: 181, alt: nil, accuracyM: nil)
        XCTAssertEqual(paths(m), ["startLocation.lat", "startLocation.lon"])
    }
    func testFinishedNeedsClosedSpansAndHashes() {
        XCTAssertEqual(paths(base(), finished: true), ["spans[0].endedBy", "spans[0].sha256"])
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `problems(finished:)` as undefined.

- [ ] **Step 3: Implement `ManifestProblems.swift`**

Report problems in manifest order (top level, then spans, then items), and within one object in the order of the rules above. Report one problem per path.

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 44 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): consistency checks for a session manifest"
```

---

### Task 9: notes.md

**Files:**
- Create: `Core/Sources/ScrivnerCore/NotesMarkdown.swift`
- Test: `Core/Tests/ScrivnerCoreTests/NotesMarkdownTests.swift`

**Interfaces:**
- Consumes: `Manifest` (Task 6), `LocalClock` (Task 1).
- Produces: `public enum NotesMarkdown { public static func render(_ manifest: Manifest) -> String }`

Format, which the test pins. The file is for people; nothing reads it back.
- Line 1: `# <title>`, then a blank line.
- Then `Started <yyyy-MM-dd> <HH:mm> (UTC<offset>, <timeZone>)`, and when there are participants a line `Participants: <codes joined with ", ">`, then a blank line.
- Then one paragraph per item, in manifest order, separated by blank lines, each beginning `**<HH:mm>**` in that item's own offset, followed by: for text, a space and the text as typed; for a marker, a space and one of `Recording started`, `Paused`, `Resumed`, `Stopped`, `Interrupted (<detail>)` or `Interrupted`, `Location off`, `Location on`, in italics (`*…*`); for a photo ` [photo: <file>]`; for a video ` [video: <file>, <m:ss>]` (or without the length when it is unknown) with `, no sound` added when `sound` is false; for ink ` [handwriting: <file>]`.
- The file ends with a single newline. The title and text are written exactly as typed.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class NotesMarkdownTests: XCTestCase {
    func testRenderIsExact() throws {
        var m = ManifestCodingTests.sample()
        let p = m.items[0].placement
        var later = p; later.at = p.at.adding(milliseconds: 600_000); later.utcOffset = UTCOffset(seconds: 3600)
        m.items = [
            .marker(p, type: .recordingStarted, detail: nil),
            .text(p, text: "P-014 has run the stall since 2009.", modifiedAt: nil),
            .photo(p, file: "photos/photo-0001.heic", sha256: nil, gps: nil),
            .video(p, durationMs: 48_000, endedBy: .user, sound: true, file: "video/clip-0001.mov", sha256: nil, gps: nil),
            .video(p, durationMs: nil, endedBy: nil, sound: false, file: "video/clip-0002.mov", sha256: nil, gps: nil),
            .marker(later, type: .interrupted, detail: "phone call"),
            .ink(later, endAt: nil, file: "ink/ink-0001.png", sha256: nil, data: "ink/ink-0001.drawing", dataSha256: nil, strokes: []),
        ]
        XCTAssertEqual(NotesMarkdown.render(m), """
        # Market visit

        Started 2026-11-23 10:42 (UTC+00:00, Europe/Lisbon)
        Participants: P-014

        **10:43** *Recording started*

        **10:43** P-014 has run the stall since 2009.

        **10:43** [photo: photos/photo-0001.heic]

        **10:43** [video: video/clip-0001.mov, 0:48]

        **10:43** [video: video/clip-0002.mov, no sound]

        **11:53** *Interrupted (phone call)*

        **11:53** [handwriting: ink/ink-0001.png]

        """)
    }
    func testNotesKeepOtherScriptsAndEscapeNothing() {
        var m = ManifestCodingTests.sample()
        m.title = "Рынок *утром*"; m.participants = []
        m.items = [.text(m.items[0].placement, text: "line one\nline two with \"quotes\" and 市場", modifiedAt: nil)]
        XCTAssertEqual(NotesMarkdown.render(m), "# Рынок *утром*\n\nStarted 2026-11-23 10:42 (UTC+00:00, Europe/Lisbon)\n\n**10:43** line one\nline two with \"quotes\" and 市場\n")
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `NotesMarkdown` as undefined.

- [ ] **Step 3: Implement `NotesMarkdown.swift`**

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 46 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): notes.md rendering"
```

---

### Task 10: The folder on disk

**Files:**
- Create: `Core/Sources/ScrivnerCore/SessionStore.swift`
- Test: `Core/Tests/ScrivnerCoreTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `Manifest`, `ManifestCoding` (Task 6); `Naming` (Task 3); `SHA256Hex` (Task 4); `NotesMarkdown` (Task 9); `problems(finished:)` (Task 8).
- Produces:

```swift
public enum MediaKind: Sendable { case audio, photo, video, inkPicture, inkData }
public struct SessionFolder: Equatable, Sendable {
    public let url: URL
    public var sessionJSON: URL { get }        // session.json
    public var notes: URL { get }              // notes.md
    public func url(forRelativePath path: String) -> URL
}
public enum SessionStoreError: Error, Equatable {
    case folderExists(String), missingFile(String), inconsistent([ManifestProblem])
}
public enum SessionStore {
    public static func folderName(for manifest: Manifest) -> String
    public static func create(_ manifest: Manifest, in root: URL) throws -> SessionFolder   // makes the folder and its four subfolders, then saves
    public static func save(_ manifest: Manifest, to folder: SessionFolder) throws          // session.json and notes.md, each written atomically
    public static func load(_ folder: SessionFolder) throws -> Manifest
    public static func nextFile(_ kind: MediaKind, ext: String, in manifest: Manifest) -> String
    public static func finalize(_ manifest: Manifest, in folder: SessionFolder) throws -> Manifest
    public static func renameToMatchTitle(_ folder: SessionFolder, manifest: Manifest) throws -> SessionFolder
    public static func sessions(in root: URL) -> [SessionFolder]                            // folders holding a session.json, newest name first
}
```

Behaviour the tests pin:
- Subfolders: `audio`, `photos`, `video`, `ink`.
- `nextFile` returns the next unused name of its kind, counting what the manifest already lists: `audio/audio-001.<ext>` (3 digits), `photos/photo-0001.<ext>`, `video/clip-0001.<ext>`, `ink/ink-0001.<ext>` (4 digits). `inkPicture` and `inkData` share one counter so a picture and its data get the same number.
- `finalize` hashes every listed file, fills the hashes in, checks `problems(finished: true)`, saves and returns the manifest. A listed file that is not on disk throws `.missingFile(<relative path>)`; any problem throws `.inconsistent`.
- `renameToMatchTitle` renames the folder when its name differs from `folderName(for:)`, and returns the folder unchanged when it does not. If the target name is taken it throws `.folderExists`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ScrivnerCore

final class SessionStoreTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func closed() -> Manifest {
        var m = ManifestCodingTests.sample()
        m.spans[0].durationMs = 551_000; m.spans[0].endedBy = .stop
        return m
    }

    func testCreateSaveLoad() throws {
        let m = closed()
        let folder = try SessionStore.create(m, in: root)
        XCTAssertEqual(folder.url.lastPathComponent, "2026-11-23 1042 Market visit [0000]")
        for sub in ["audio", "photos", "video", "ink"] {
            var isDir: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent(sub).path, isDirectory: &isDir) && isDir.boolValue, sub)
        }
        XCTAssertEqual(try String(contentsOf: folder.sessionJSON, encoding: .utf8), ManifestCoding.encode(m))
        XCTAssertEqual(try String(contentsOf: folder.notes, encoding: .utf8), NotesMarkdown.render(m))
        XCTAssertEqual(try SessionStore.load(folder), m)
        XCTAssertThrowsError(try SessionStore.create(m, in: root)) {
            XCTAssertEqual($0 as? SessionStoreError, .folderExists("2026-11-23 1042 Market visit [0000]"))
        }
        XCTAssertEqual(SessionStore.sessions(in: root).map(\.url.lastPathComponent), [folder.url.lastPathComponent])
    }
    func testNextFileCountsWhatIsListed() {
        var m = closed()
        XCTAssertEqual(SessionStore.nextFile(.audio, ext: "m4a", in: m), "audio/audio-002.m4a")
        XCTAssertEqual(SessionStore.nextFile(.photo, ext: "heic", in: m), "photos/photo-0001.heic")
        m.items.append(.photo(m.items[0].placement, file: "photos/photo-0001.heic", sha256: nil, gps: nil))
        m.items.append(.ink(m.items[0].placement, endAt: nil, file: "ink/ink-0001.png", sha256: nil, data: "ink/ink-0001.drawing", dataSha256: nil, strokes: []))
        XCTAssertEqual(SessionStore.nextFile(.photo, ext: "heic", in: m), "photos/photo-0002.heic")
        XCTAssertEqual(SessionStore.nextFile(.video, ext: "mov", in: m), "video/clip-0001.mov")
        XCTAssertEqual(SessionStore.nextFile(.inkPicture, ext: "png", in: m), "ink/ink-0002.png")
        XCTAssertEqual(SessionStore.nextFile(.inkData, ext: "drawing", in: m), "ink/ink-0002.drawing")
    }
    func testFinalizeHashesFilesAndRefusesGaps() throws {
        var m = closed()
        var photo = m.items[0].placement; photo.id = "00000000-0000-7000-8000-000000000003"
        m.items.append(.photo(photo, file: "photos/photo-0001.heic", sha256: nil, gps: nil))
        let folder = try SessionStore.create(m, in: root)
        XCTAssertThrowsError(try SessionStore.finalize(m, in: folder)) {
            XCTAssertEqual($0 as? SessionStoreError, .missingFile("audio/audio-001.m4a"))
        }
        try Data("audio".utf8).write(to: folder.url(forRelativePath: "audio/audio-001.m4a"))
        try Data("photo".utf8).write(to: folder.url(forRelativePath: "photos/photo-0001.heic"))
        let done = try SessionStore.finalize(m, in: folder)
        XCTAssertEqual(done.spans[0].sha256, SHA256Hex.of(Data("audio".utf8)))
        guard case .photo(_, _, let hash, _) = done.items[1] else { return XCTFail() }
        XCTAssertEqual(hash, SHA256Hex.of(Data("photo".utf8)))
        XCTAssertEqual(try SessionStore.load(folder), done)
        XCTAssertEqual(done.problems(finished: true), [])

        var open = m; open.spans[0].durationMs = nil; open.spans[0].endedBy = nil
        XCTAssertThrowsError(try SessionStore.finalize(open, in: folder)) {
            guard case .inconsistent(let problems)? = $0 as? SessionStoreError else { return XCTFail() }
            XCTAssertEqual(problems.map(\.path), ["spans[0].endedBy"])
        }
    }
    func testRenameToMatchTitle() throws {
        var m = closed()
        let folder = try SessionStore.create(m, in: root)
        XCTAssertEqual(try SessionStore.renameToMatchTitle(folder, manifest: m), folder)
        m.title = "Fish stall: second visit"
        let renamed = try SessionStore.renameToMatchTitle(folder, manifest: m)
        XCTAssertEqual(renamed.url.lastPathComponent, "2026-11-23 1042 Fish stall- second visit [0000]")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamed.sessionJSON.path))
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `SessionStore`, `SessionFolder` and `MediaKind` as undefined.

- [ ] **Step 3: Implement `SessionStore.swift`**

`save` writes each file to a temporary name in the same folder and renames it into place. `renameToMatchTitle` does not rewrite `session.json`; the caller saves. `sessions(in:)` ignores anything that is not a folder holding `session.json`.

- [ ] **Step 4: Run to see it pass**

Run: `swift test --package-path Core`
Expected: `Executed 50 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Core && git commit -m "feat(core): the session folder on disk"
```

---

### Task 11: The schema, the example and the samples that must fail

**Files:**
- Create: `Core/Sources/ScrivnerCore/ExampleSession.swift`, `format/field-session.v1.schema.json`, `format/README.md`, `format/package.json`, `format/validate.mjs`, `format/invalid/*.json`, `format/examples/2026-11-23 1042 Market visit [<id4>]/…`
- Test: `Core/Tests/ScrivnerCoreTests/ExampleSessionTests.swift`
- Modify: `.gitignore` (add `node_modules/`)

**Interfaces:**
- Consumes: everything from Tasks 1 to 10.
- Produces:

```swift
public enum ExampleSession {
    /// The scripted "Market visit" session, finished, with placeholder media, written under `root`.
    public static func write(in root: URL) throws -> SessionFolder
}
```

The script, with `SeededIdSource(seed: 2026)`, device `iPhone18,1` / `iOS 27.1` / `0.1.0`, time zone `Europe/Lisbon`, offset `+00:00`, start location lat 38.7223, lon -9.1393, alt 12, accuracy 5, and times in seconds after `2026-11-23T10:42:10.120Z`:

| At | What |
|---|---|
| 0 | create "Market visit" with participant `P-014`; start recording `audio/audio-001.m4a` |
| 65 | text: `P-014 has run the stall since 2009. Took it over from her aunt, who still does the early shift on Saturdays.` |
| 185 | photo `photos/photo-0001.heic` with the start location |
| 228 | text: `Prices are handwritten every morning. Says the card reader "scares off the regulars".` |
| 430 to 478 | video clip `video/clip-0001.mov`, ended by the user |
| 512 | text: `Asked me not to photograph the ledger.` |
| 551 | pause |
| 560 | location off |
| 600 | text: `Off the record: the lease runs out in March.` |
| 640 to 652 | video clip `video/clip-0002.mov` (no sound), ended by the user |
| 700 | resume, `audio/audio-002.m4a` |
| 760 | photo `photos/photo-0002.heic`, no location |
| 800 | stop |

Each placeholder media file's content is the ASCII text `placeholder for <relative path>\n`. Real media arrives with the checker plan.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ScrivnerCore

final class ExampleSessionTests: XCTestCase {
    /// <repo>/format/examples, found from this file's own path.
    static let examples = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("format/examples")

    func testExampleIsConsistentAndMatchesTheCommittedCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("example-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try ExampleSession.write(in: root)
        let manifest = try SessionStore.load(folder)
        XCTAssertEqual(manifest.problems(finished: true), [])
        XCTAssertEqual(manifest.spans.map(\.durationMs), [551_000, 100_000])
        XCTAssertEqual(manifest.items.count, 13)
        XCTAssertTrue(folder.url.lastPathComponent.hasPrefix("2026-11-23 1042 Market visit ["))

        let committed = Self.examples.appendingPathComponent(folder.url.lastPathComponent)
        if ProcessInfo.processInfo.environment["UPDATE_EXAMPLE"] == "1" {
            try? FileManager.default.removeItem(at: committed)
            try FileManager.default.createDirectory(at: Self.examples, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: folder.url, to: committed)
        }
        var files: [String] = ["session.json", "notes.md"]
        files += manifest.spans.map(\.file)
        for item in manifest.items {
            switch item {
            case .photo(_, let file, _, _): files.append(file)
            case .video(_, _, _, _, let file, _, _): files.append(file)
            default: break
            }
        }
        for file in files {
            XCTAssertEqual(try? Data(contentsOf: committed.appendingPathComponent(file)),
                           try Data(contentsOf: folder.url.appendingPathComponent(file)),
                           "format/examples is out of date for \(file): run the tests once with UPDATE_EXAMPLE=1")
        }
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Core`
Expected: build failure naming `ExampleSession` as undefined.

- [ ] **Step 3: Implement `ExampleSession.swift`, then create the committed copy**

Run: `UPDATE_EXAMPLE=1 swift test --package-path Core`, then `swift test --package-path Core`
Expected: `Executed 51 tests, with 0 failures` both times, and a folder under `format/examples/`.

- [ ] **Step 4: Write `format/field-session.v1.schema.json`**

JSON Schema draft 2020-12. It must say exactly what `ManifestCoding.decode` enforces about shape: the required and optional keys of Task 6, `additionalProperties: false` everywhere, `format` const `ao-field-session`, `version` const `1`, ids matching `^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`, instants matching `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$`, offsets matching `^[+-]\d{2}:\d{2}$`, hashes matching `^[0-9a-f]{64}$`, relative paths matching `^(?![./])(?!.*//)(?!.*/\.)[^\\]+$`, items as a `oneOf` over the five kinds told apart by a `kind` const, `spanId` and `offsetMs` each requiring the other (`dependentRequired`), `durationMs` and `endedBy` on a span each requiring the other, `bounds` with exactly four numbers, `lat` in -90…90 and `lon` in -180…180, whole numbers of at least 0 for `offsetMs` and `durationMs`. Give every property a one-line `description` in plain language, taken from spec section 6.2.

- [ ] **Step 5: Write the samples that must fail**

Each file in `format/invalid/` is the example's `session.json` with one thing wrong, named for the fault: `missing-device.json`, `wrong-version.json`, `unknown-top-level-key.json`, `unknown-item-kind.json`, `instant-without-milliseconds.json`, `uppercase-hash.json`, `offset-without-span.json`, `span-duration-without-ended-by.json`, `absolute-file-path.json`, `hidden-file-path.json`, `bounds-with-three-numbers.json`, `latitude-out-of-range.json`, `negative-offset.json`, `video-without-sound.json`.

- [ ] **Step 6: Write `format/package.json` and `format/validate.mjs`**

`package.json`: private, `"type": "module"`, one dependency `ajv` pinned to an exact 8.x version, script `"validate": "node validate.mjs"`.

`validate.mjs`: compiles the schema with Ajv's 2020 build (`ajv/dist/2020.js`), strict mode on. Every `examples/*/session.json` must validate; every `invalid/*.json` must not. Prints one line per file (`ok  <path>` or `FAIL <path>: <reason>`), then `SCHEMA CHECK OK (<n> valid, <m> rejected)` and exits 0, or `SCHEMA CHECK FAILED` and exits 1.

- [ ] **Step 7: Run the schema check and see it pass**

Run: `(cd format && npm install --no-audit --no-fund && npm run validate)`
Expected: last line `SCHEMA CHECK OK (1 valid, 14 rejected)`.

- [ ] **Step 8: Prove the check bites**

Temporarily copy the example's `session.json` to `format/invalid/should-not-be-here.json` and run `npm run validate`.
Expected: `FAIL invalid/should-not-be-here.json` and exit 1. Delete the copy and run again; expected OK.

- [ ] **Step 9: Write `format/README.md`**

Half a page in plain language: what the folder is, that the schema is the single definition of `session.json`, how to run the two checks, that the example's media files are placeholders for now, and how to regenerate the example (`UPDATE_EXAMPLE=1 swift test --package-path Core`).

- [ ] **Step 10: Commit**

```bash
git add Core format .gitignore && git commit -m "feat(format): session.json schema, worked example and samples that must fail"
```

---

### Task 12: Decision record, Mac build and automatic checks

**Files:**
- Create: `docs/adr/0003-session-folder-format.md`, `.github/workflows/core.yml`
- Modify: `tools/mac-build.sh` (run the Core tests), `README.md` (one paragraph on `Core/` and `format/`), `.claude/settings.json` (allow `npm run validate *` and `npm install *`)

**Interfaces:**
- Consumes: the commands from Tasks 1 to 11.

- [ ] **Step 1: Write `docs/adr/0003-session-folder-format.md`**

Sections Status (Accepted), Date, Context, Decision, Consequences. Decision points to record: the schema file is the single definition and the Swift decoder mirrors it; `session.json` is written by our own deterministic writer with keys in reading order, so the file is identical on every platform and diffs are small; nil values are left out; one audio file per unbroken span; items carry both the instant and the position on the audio; hashes are filled in when a session is finished; media files are named by kind and number. Consequences: a change to the format means changing the schema, the decoder, the writer and the example together, and a new `version`; numbers 0001 and 0002 are reserved for the stage 0 decisions.

- [ ] **Step 2: Add the Core tests to `tools/mac-build.sh`**

Add a step named `Core tests` running `swift test --package-path Core`, straight after the setup check.

- [ ] **Step 3: Write `.github/workflows/core.yml`**

Runs on pushes and pull requests. Job `core-tests`: `runs-on: ubuntu-24.04`, `container: swift:6.4.3-noble`, checkout, `swift test --package-path Core`. Job `schema-check`: `runs-on: ubuntu-24.04`, checkout, Node 22, `npm install --no-audit --no-fund` and `npm run validate` in `format/`.

- [ ] **Step 4: Update `README.md` and `.claude/settings.json`**

- [ ] **Step 5: Run everything once more**

Run: `swift test --package-path Core && (cd format && npm run validate) && bash -n tools/mac-build.sh`
Expected: `Executed 51 tests, with 0 failures`, then `SCHEMA CHECK OK (1 valid, 14 rejected)`, and no output from `bash -n`.

- [ ] **Step 6: Commit**

```bash
git add docs/adr tools/mac-build.sh README.md .claude/settings.json .github && git commit -m "docs: session folder format decision; run the core checks on the Mac and automatically"
```
