# Running the workbench's own import code over a session folder

- **Date:** 2026-11-24
- **Workbench:** `MaquisChat/AlexandrineOxiana` at commit `0ad6506`
- **Session folder:** the worked example, `format/examples/2026-11-23 1042 Market visit [455d]`
- **Command:** `tools/workbench-check.sh <workbench checkout>`

## What this is

The design spec (section 6.4) first checked compatibility by reading the workbench's import code. This record goes one step further: it runs that code. The script calls three things from a local copy of the workbench, without importing anything anywhere and without changing the workbench:

- its device import's own scan of a folder (which files it picks up, what kind of item each becomes, its title, capture time and time zone);
- its own reader of the place written inside a media file;
- its own cleaning of folder names.

The worked example is set where the local clock is 5 hours 45 minutes ahead of UTC, so that a time read as local when it is UTC, or the other way round, cannot hide.

## Result: one fault found, in how the workbench reads the time of an audio file

```
Workbench at commit 0ad6506
Session folder: 2026-11-23 1042 Market visit [455d]
== What the workbench's device import finds
FAIL audio/audio-001.m4a: capture time 2026-11-22T23:12:10.000Z, but session.json says 2026-11-23T04:57:10.120Z
FAIL audio/audio-002.m4a: capture time 2026-11-22T23:23:50.000Z, but session.json says 2026-11-23T05:08:50.120Z
ok   photos/photo-0001.heic: field-photo, "2026-11-23 iPhone 17 Pro - photo-0001", image/heic, taken 2026-11-23T05:00:15.120Z (+05:45), at 27.7046, 85.3076, 1300 m, Apple iPhone 17 Pro
ok   photos/photo-0002.heic: field-photo, "2026-11-23 iPhone 17 Pro - photo-0002", image/heic, taken 2026-11-23T05:09:50.120Z (+05:45), no place, Apple iPhone 17 Pro
ok   video/clip-0001.mov: field-video, "2026-11-23 iPhone 17 Pro - clip-0001", video/quicktime, taken 2026-11-23T05:04:20.000Z (+05:45), at 27.7046, 85.3076, 1300 m, Apple iPhone 17 Pro
ok   video/clip-0002.mov: field-video, "2026-11-23 iPhone 17 Pro - clip-0002", video/quicktime, taken 2026-11-23T05:07:50.000Z (+05:45), no place, Apple iPhone 17 Pro
== Folder names through the workbench's own cleaning
18 of 18 folder names are left exactly as they are
WORKBENCH CHECK FAILED (2 failures, workbench 0ad6506)
```

### What works

- **Photos and video clips arrive correctly.** Each becomes its own item of the right kind, with the right moment, the right time zone, the right place (and no place where location was off), and the device named. The titles the workbench gives them read well: `2026-11-23 iPhone 17 Pro - photo-0001`.
- **Audio files are picked up as recordings**, with the right time zone and device, and no place.
- **Nothing else is picked up.** `session.json` and `notes.md` are left alone, as expected.
- **Nothing is mistaken for a Live Photo pair.**
- **Folder names survive.** 18 awkward session titles (slashes, reserved Windows names, very long titles, emoji, right-to-left marks) give folder names that the workbench's own cleaning leaves exactly as they are. Two small differences were found and fixed on the recorder's side on the way: the workbench drops the invisible characters that change text direction, and counts the byte-order mark as a space; the recorder now does the same.

### The fault

**The workbench reads the time of an audio recording wrong by the time-zone offset.** In the example it puts the first recording at 23:12 UTC the evening before, when it began at 04:57 UTC (10:42 local time): out by 5 hours 45 minutes, the size of the offset. At UTC+0 the fault is invisible, which is why it had not shown before.

Why: a recording's file carries two times. One is the standard creation time, which is always in UTC. The other is Apple's creation date, which is local time with its offset. The library the workbench reads tags with knows the first is UTC for video files, but not for audio files: for audio it hands the UTC reading back as if it were local time. The workbench takes that first.

This is not specific to this recorder. Any iPhone audio file that carries both times would be read the same way when imported outside UTC+0.

What it means for now: until the workbench is fixed, an audio recording imported from a session folder shows a capture time that is wrong by the time-zone offset. The audio itself, and everything in `session.json` (which is what will place notes and photos beside the transcript), are unaffected.

### The fix, on the workbench's side

Two lines of code (and three of comment) in `packages/library/src/extract/exif.ts`: when Apple's creation date states its time zone, use it as the capture time ahead of the standard creation time. The change is in `docs/compatibility/workbench-audio-time.patch`.

It was tried on a local copy of the workbench, which was then put back as it was:

- with the change, the same check gives `WORKBENCH CHECK OK (6 files, 18 folder names, workbench 0ad6506)` (the script now adds "with local changes" to that line when the copy differs from its commit);
- the workbench's own tests for that file still pass (32 passed).

An independent reviewer confirmed the diagnosis and tried the change on a separate copy: both audio files come out at the right moment, and what the workbench reads from the four photos and clips is unchanged. For a Live Photo's clip it gives the same moment as before; photos and files without Apple's keys are untouched. The patch does not yet include a test for the workbench's own test suite.

This session cannot write to the workbench's repository, so the change has not been made there. It needs to be applied in the workbench project.

## What this check does not show

- It does not run a whole import into a workbench library. It runs the scan that decides what an import would contain.
- Typed notes, placing things beside the transcript, and importing a zip are not in the workbench yet (design spec, section 9).
- Handwriting pictures (`.png`) would arrive as field photos, as section 6.4 already says. The example has none.
- The example's media were made on a computer to match what an iPhone writes. The same check must be run on a real session folder from the phone at the end of stage 1.

## Running it again

```bash
tools/workbench-check.sh /path/to/AlexandrineOxiana
```

Give a second argument to check another session folder. The workbench copy needs its dependencies installed (`pnpm install`). Run it whenever either side changes how it writes or reads media files, and add the result below.
