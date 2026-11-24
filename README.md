# Alexandrine Scrivner

A field notebook for iPhone and iPad with a recorder running underneath: audio records continuously while you type or handwrite notes, take photos and shoot video clips, and everything is stamped with the time it was made so it can later be placed beside the transcript in the research workbench.

The design is in `docs/superpowers/specs/`. Start with `2026-11-23-field-notebook-recorder-design.md`.

The work is done from written plans in `docs/superpowers/plans/`, one stage at a time. Decisions made along the way are recorded in `docs/adr/`.

Two parts need no Mac and are checked automatically on every push:

- `Core/` is the part of the recorder that has nothing to do with the screen or the microphone: times, ids, file names, the session's timeline, and reading and writing the session folder. Check it with `swift test --package-path Core`.
- `format/` defines the session folder that the recorder writes and the research workbench reads, with a worked example. See `format/README.md`.

Building the app needs a Mac. The one-time setup is described in plain language in `docs/guides/mac-setup.md`.
