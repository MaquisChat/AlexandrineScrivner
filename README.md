# Alexandrine Scrivner

A field notebook for iPhone and iPad with a recorder running underneath: audio records continuously while you type or handwrite notes, take photos and shoot video clips, and everything is stamped with the time it was made so it can later be placed beside the transcript in the research workbench.

The design is in `docs/superpowers/specs/`. Start with `2026-11-23-field-notebook-recorder-design.md`.

The work is done from written plans in `docs/superpowers/plans/`, one stage at a time. Decisions made along the way are recorded in `docs/adr/`.

Two parts need no Mac and are checked automatically on every push:

- `Core/` is the part of the recorder that has nothing to do with the screen or the microphone: times, ids, file names, the session's timeline, and reading and writing the session folder. Check it with `swift test --package-path Core`.
- `format/` defines the session folder that the recorder writes and the research workbench reads, with a worked example. See `format/README.md`.

A session folder brought over from the phone can be checked before it goes into the workbench. The checker reads the folder and says in plain sentences anything that is wrong with it, including a photo, clip or recording whose time or place inside the file disagrees with the session's own record:

```bash
tools/mac-check-session.sh ~/Desktop/Sessions
```

Whether the workbench can take in what the recorder writes is tested by running the workbench's own import code over the worked example. The latest result is in `docs/compatibility/workbench-check.md`.

`App/` is the notebook app itself. In this stage it has every screen, but its microphone, camera and location are stand-ins: it writes a silent recording and a drawn picture where the real ones will go, and stores no place. It says so in a red line on every screen, and must not be used for a real interview yet. That lets the whole app be built, walked through and photographed automatically in an iPhone simulator on every push (`tools/mac-walkthrough.sh`), before the real microphone and camera are wired in.

Building the app needs a Mac. The one-time setup is described in plain language in `docs/guides/mac-setup.md`.
