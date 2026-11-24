# The session folder format

This folder defines what the recorder writes and what the research workbench reads: one folder per session, with a `session.json` file that lists everything on the page and where each thing sits on the audio.

## What is here

- `field-session.v1.schema.json` defines the shape of `session.json`: which keys exist, which are required, and what each value looks like. Every field has a plain-language description inside it. A few rules cannot be written in a schema; they are listed below.
- `examples/` holds one complete worked session, "Market visit": two stretches of recording with a pause between them, typed notes, two photos and two video clips. It is set where the local clock is not UTC (10:42 in the morning at UTC+05:45), so every conversion between local time and UTC shows.
- `valid/` holds two more `session.json` files exactly as the recorder writes them: `all-kinds.json` uses every key the format has, including handwriting and a recording recovered after a crash; `unfinished.json` is a session caught mid-recording.
- `invalid/` holds copies of the example's `session.json` with one thing wrong in each. The schema must reject every one of them, and so must the recorder's own reader.
- `validate.mjs` is the check that the schema accepts the first three and rejects the broken copies.
- `tools/make-invalid.py` writes the broken copies from the example.
- `tools/make-example-media.py` made the example's audio, photo and video files.

The design behind the format is in `docs/superpowers/specs/2026-11-23-field-notebook-recorder-design.md`, section 6, and the reasons for the main choices are in `docs/adr/0003-session-folder-format.md`.

## The two checks

Both run from the top of the repository.

The recorder's own code writes the example and compares it with the copy kept here, byte for byte:

```bash
swift test --package-path Core
```

The schema accepts the example and rejects the broken copies:

```bash
cd format && npm install --no-audit --no-fund && npm run validate
```

The second check ends with `SCHEMA CHECK OK (3 valid, 15 rejected)` when all is well.

## Rules the schema cannot express

A `session.json` can have the right shape and still be wrong. A reader should also check these. The recorder does, in `Core/Sources/ScrivnerCore/ManifestProblems.swift`.

- Every id is different from every other id in the file.
- Every `spanId` names a span in `spans`, and its `offsetMs` is not past the end of that span's audio.
- Only the last span may be open, that is, have no `endedBy` and no `durationMs`.
- No file is listed twice.
- **A session is finished when no span is open and every listed file has its hash.** Only a finished session should be imported. An unfinished one, like `valid/unfinished.json`, has the right shape, so the schema accepts it; it means the app was still recording or was cut off, and the app repairs and finishes it the next time it opens.

## Versions

Both the schema and the recorder's reader refuse keys they do not know. That is deliberate: a reader never half-understands a file. It also means that **any change to what `session.json` may contain, even one new optional key, is a new `version` number**, with a new schema file beside this one. A reader refuses a version it does not know and says so, rather than guessing.

## The example's media are real files, but nothing in them is recorded from life

The audio in the example is a quiet tone, the photos are flat colours and the clips are a test pattern. They are real files of the right kinds and lengths (about 1.3 MB in all), and each carries inside it the times and places an iPhone's own camera would write, agreeing with `session.json`. That is what the research workbench reads when it imports a folder, so the example can be put through the workbench's import as it stands.

## Checking a session folder

`scrivner-check` reads a session folder and says, in plain sentences, anything that is wrong with it: a `session.json` that does not read, a missing or changed file, and (with `--media`) a media file whose time, time zone or place disagrees with `session.json`. From the top of the repository:

```bash
swift run --package-path Core scrivner-check --media --exiftool "$(tools/get-exiftool.sh | tail -1)" format/examples
```

The last line is `SESSION CHECK OK` or `SESSION CHECK FAILED`. `tools/get-exiftool.sh` fetches ExifTool, the program that reads tags inside media files; it is the same build the workbench uses.

## Changing the format

The example and the files in `valid/` are generated, not written by hand. After a deliberate change to the format, regenerate them, then the broken copies, and read the difference before committing:

```bash
UPDATE_EXAMPLE=1 swift test --package-path Core
```

```bash
python3 format/tools/make-invalid.py .
```

The example's media files are kept as they are when the example is regenerated; only `session.json` and `notes.md` are rewritten. If the change moves a time, a place or a length, make the media again (this needs ffmpeg and the Python package `pillow-heif`) and then regenerate once more so the checksums match:

```bash
python3 format/tools/make-example-media.py "$(ls -d format/examples/*/)" "$(tools/get-exiftool.sh | tail -1)"
```

A change to the format means changing the schema, the Swift reader and writer in `Core/`, and these files together, under a new `version` number (see Versions above). Until the first version of the app is in use, version 1 is still being settled and is changed in place.
