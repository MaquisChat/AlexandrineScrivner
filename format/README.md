# The session folder format

This folder defines what the recorder writes and what the research workbench reads: one folder per session, with a `session.json` file that lists everything on the page and where each thing sits on the audio.

## What is here

- `field-session.v1.schema.json` defines the shape of `session.json`: which keys exist, which are required, and what each value looks like. Every field has a plain-language description inside it. A few rules cannot be written in a schema; they are listed below.
- `examples/` holds one complete worked session, "Market visit": two stretches of recording with a pause between them, typed notes, two photos and two video clips.
- `valid/` holds two more `session.json` files exactly as the recorder writes them: `all-kinds.json` uses every key the format has, including handwriting and a recording recovered after a crash; `unfinished.json` is a session caught mid-recording.
- `invalid/` holds copies of the example's `session.json` with one thing wrong in each. The schema must reject every one of them, and so must the recorder's own reader.
- `validate.mjs` is the check that the schema accepts the first three and rejects the broken copies.
- `tools/make-invalid.py` writes the broken copies from the example.

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

## The example's media files are placeholders

The audio, photo and video files in the example are one-line text files with the right names, not real recordings. They are there so the folder has the right shape and the checksums in `session.json` have something to match. Real media, with real capture times and locations inside the files, come from the phone and will replace them once the app can record.

## Changing the format

The example and the files in `valid/` are generated, not written by hand. After a deliberate change to the format, regenerate them, then the broken copies, and read the difference before committing:

```bash
UPDATE_EXAMPLE=1 swift test --package-path Core
```

```bash
python3 format/tools/make-invalid.py .
```

A change to the format means changing the schema, the Swift reader and writer in `Core/`, and these files together, under a new `version` number (see Versions above). Until the first version of the app is in use, version 1 is still being settled and is changed in place.
