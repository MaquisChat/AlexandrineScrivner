# The session folder format

This folder defines what the recorder writes and what the research workbench reads: one folder per session, with a `session.json` file that lists everything on the page and where each thing sits on the audio.

## What is here

- `field-session.v1.schema.json` is the single definition of `session.json`. If this file and anything else disagree, this file is right. Every field has a plain-language description inside it.
- `examples/` holds one complete worked session, "Market visit": two stretches of recording with a pause between them, typed notes, two photos and two video clips.
- `invalid/` holds copies of the example's `session.json` with one thing wrong in each. The schema must reject every one of them.
- `validate.mjs` is the check that the schema accepts the example and rejects the broken copies.

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

The second check ends with `SCHEMA CHECK OK (1 valid, 14 rejected)` when all is well.

## The example's media files are placeholders

The audio, photo and video files in the example are one-line text files with the right names, not real recordings. They are there so the folder has the right shape and the checksums in `session.json` have something to match. Real media, with real capture times and locations inside the files, come from the phone and will replace them once the app can record.

## Changing the format

The example is generated, not written by hand. After a deliberate change to the format, regenerate it and read the difference before committing:

```bash
UPDATE_EXAMPLE=1 swift test --package-path Core
```

A change to the format means changing the schema, the Swift reader and writer in `Core/`, and the example together. A change that an older reader could misread also needs a new `version` number.
