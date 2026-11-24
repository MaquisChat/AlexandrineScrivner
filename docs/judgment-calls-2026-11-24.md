# Judgment calls made while building, 24 November 2026

Everything below was decided without asking, because the instruction was to proceed as fast as possible. Each entry says what was decided, why, and what it costs if it was the wrong call. None of it is hard to change.

This is the complete record, so it uses the names found in the code. The seven at the top are the ones most worth your eye; the rest is here so that nothing decided on your behalf is hidden. Entries headed *Left for later* are small things an independent reviewer noticed that were not fixed.

## Most worth a look

1. **All four plans below were carried out without waiting for you to read them first.** Each was then read by an independent reviewer, and what the reviewers found was fixed. The plans are in `docs/superpowers/plans/`.
2. **A session you have not named keeps an empty title** in its file and shows its date and time instead (`2026-11-23 10:42`). The format's own documents say so. If the workbench reads titles, it needs the same rule.
3. **A session started with location off says “Location off” as its second line**, and a reopened session never turns location back on by itself.
4. **The worked example moved from Lisbon to Kathmandu** (UTC+5:45), so that mistakes between local time and UTC cannot hide. That is how the workbench's audio-time fault was found.
5. **Sessions are left out of iCloud and computer backups.** The design said so and asked you to confirm. The only copies are the one on the phone and the ones you share.
6. **The plain layout's top is not as in the mockup.** Its controls sit on a line of their own above the title, so that a long title or large text cannot push one off the screen, and the title scrolls away with the page to leave room for writing.
7. **The app has a dark appearance**, which the mockups did not show. It follows the phone's setting.

## The session folder format and the core library (branch `foundations`)

- **Started executing without the plan-review handoff.** *Why:* The owner's standing instruction was to proceed as fast as possible with approvals set, and stage 0 is blocked on their Mac. *If wrong:* The owner reviews this plan after the fact and asks for changes.
- **Work in place on branch foundations, no extra worktree (isolated cloud checkout).**
- **NeedsRecovery is also true when a resumed manifest has a clip with no endedBy, not only an open span.** *Why:* Otherwise a clip left open by a crash while paused could never be closed. *If wrong:* One extra recoverAfterCrash call in the app.
- **The closing marker's offsetMs is capped at the span's duration when audioDurationMs is shorter than the host-clock length.** *Why:* Keeps the manifest consistent under Task 8's rule 3. *If wrong:* None visible.
- **The schema's item definition picks the shape by kind with if/then instead of a plain oneOf.** *Why:* Same files accepted and rejected (1 valid, 14 rejected), but the check now names the actual fault instead of one error per branch. *If wrong:* A reader of the schema meets a slightly less familiar construct.
- **.claude/settings.json left unchanged.** *Why:* Adding the two npm allow rules was refused by the session's permission check, and the refusal is not mine to work around. *If wrong:* A Claude session on the Mac asks once before running npm install / npm run validate. Reported to the owner.
- **C1 is fixed by moving late items to the end of the audio that was kept, not by allowing positions past the end.** *Why:* Keeps "a position is never past the end of its audio" as something an importer can rely on; the item's own time is untouched. *If wrong:* An importer that wanted the true distance past the end has to work it out from `at`.
- **When the audio's length cannot be read after a crash, the span is taken to be as long as the last thing placed on it (it was 0).** *If wrong:* DurationMs differs from the real file until the app can read it; the session checker in the next plan compares the two.
- **The Task 11 ruling is reversed: the schema's item definition is `oneOf` again, because the workbench is TypeScript and type generators read `oneOf` but commonly ignore if/then; the schema check now re-checks a failing item against the one shape its kind names, so the printed reason is still the real fault.** *If wrong:* None seen; the same files are accepted and rejected.
- **Save checks that the text can be read back, not that it reads back equal.** *Why:* An offset from UTC with odd seconds would otherwise block every save. *If wrong:* A value that changes on the round trip goes unnoticed.
- **File hashing now runs each chunk inside an autorelease pool on Apple platforms, on the reviewer's suspicion and without a failing test (it cannot be shown on Linux).** *If wrong:* None, behaviour is unchanged; still to be confirmed on the Mac by hashing a 2 GB file and watching memory.
- **The reviewer set aside "does Naming.sanitize match the workbench's own cleaning".** *Why:* It will be compared by running the workbench's sanitizeSegment against ours (session checker plan, Task 8). *If wrong:* A folder name the workbench would have cleaned differently.
- **The reviewer set aside media metadata inside files and the session checker.** *Why:* Both are the next plan (2026-11-24-session-checker.md).
- **The reviewer set aside zip export, the exported badge, file protection while locked, backup exclusion, how often the app saves, concurrent saves, and a folder moved in Files mid-session.** *Why:* All belong to the stage 1 app plan. Noted for it: saves replace the file, so protection and backup settings must sit on the folder. *If wrong:* None now.
- **The reviewer set aside spec 5.5's "a marker says why" for clip ends.** *Why:* The clip's own `endedBy` is the record and the page shows it from there; no separate marker item. *If wrong:* Add markers in stage 2.
- **The reviewer set aside deleting a note or photo (the spec is silent).** *Why:* Nothing can be deleted today except things whose files never reached the disk; whether the owner can delete a note or photo is a stage 1 question for the owner. *If wrong:* An API to add.
- **The reviewer set aside HTML or Markdown typed into notes.** *Why:* The plan's choice stands: notes.md escapes nothing. *If wrong:* A note with markup renders oddly in a viewer.
- **The reviewer set aside compiling Core on Apple platforms and the CryptoKit branch.** *Why:* A macOS job is added to the automatic checks so it runs on every push.
- **The reviewer set aside drift between the host clock and the audio's sample clock.** *Why:* It depends on the stage 0 audio decision.
- **The reviewer could not verify that failing tests were seen first, or that the checks run on GitHub.** *Why:* RED was seen for every task as it was done, and run 45427111881 passed on GitHub.

*Left for later:*

- NextFile counts only what the manifest lists, so the name of an unlisted leftover file can be handed out again.
- Finalize hashes files before it validates their paths, and load runs no consistency checks.
- Finalize accepts a clip with no endedBy, while reopening the same session reports a crash.
- The folder name uses the id's last four characters unsanitized; shortening a very long title is slow (about 6 s for 40,000 characters in a debug build); bidi and zero-width characters are kept.
- An instant outside years 0000 to 9999 is written as text the reader refuses.
- Create leaves an empty folder behind if the first save fails (suspected).
- Changing only the capitals of a title on a case-insensitive disk may make the rename fail (suspected; needs the Mac).
- The example's empty ink/ folder is not in git.
- In a Markdown viewer the first two lines of notes.md, and notes with several lines, run together.
- The ledger's evidence lines for tasks 2 to 12 quote the Swift Testing summary line, not the XCTest count; the suite did pass each time.

## The session checker and the worked example (branch `checker`)

- **Started executing without the plan-review handoff.** *Why:* The owner's standing instruction is to proceed as fast as possible with approvals set. *If wrong:* The owner reviews this plan after the fact and asks for changes.
- **The worked example moves from Lisbon (UTC+0) to Kathmandu (UTC+05:45), so that every local-time conversion in the format is exercised by the example and by the workbench check.** *If wrong:* An invented example in a different invented place.
- **An unfinished session is one PROBLEM, not a warning as the plan first said.** *Why:* Format/README.md says only a finished session should be imported, so the verdict must not be OK; "unfinished" also covers a stopped session whose files have no checksums yet. *If wrong:* The checker fails a folder someone only wanted to look at.
- **The workbench check FAILS today, and is recorded as failing: the workbench at 0ad6506 reads an audio file's time wrong by the UTC offset (its tag library treats QuickTime's UTC creation time as local for audio). The recorder's files follow the QuickTime convention and are left as they are; a four-line fix for the workbench is kept in docs/compatibility/workbench-audio-time.patch and was verified on a local copy, which was then restored.** *If wrong:* If real iPhone audio is in fact written differently, the patch is still harmless and the recorder's tags can be changed in stage 1.
- **Folder names are compared by asking whether the workbench's own cleaning leaves the recorder's folder names unchanged, not whether the two cleaning functions give identical output for every title.** *Why:* The recorder keeps the [id] tag and shortens the title to fit, which the workbench's function does not do. *If wrong:* None found; 18 awkward titles pass.
- **A Live Photo identifier on a single file is now a warning, and a problem only when a photo and a clip in the session share one.** *Why:* That is the only case in which the workbench joins files, and the reviewer pointed out that iOS may put an identifier on every photo, which would have failed every session. *If wrong:* A lone identifier that mattered is only warned about.
- **A place found in an unusual part of a file is a problem when session.json has no place for that file (or it is audio), and a warning when it has one and the proper tag agrees.** *If wrong:* A second, different place hidden beside the right one is only warned about.
- **In a folder of sessions, a subfolder with no session.json is reported only if it looks like a session (named the way the recorder names them, or holding audio/, photos/, video/ or ink/); other folders are left alone, so keeping unrelated folders beside sessions does not fail the check.** *If wrong:* A damaged session folder that has also been renamed and emptied of its subfolders is passed over.
- **The reviewer set aside whether iOS can write the creation-date, make and model keys into an .m4a, whether the creation time it sets itself falls within a second of the session's, and whether a place set through its common key lands where the checker expects.** *Why:* All three are for stage 1c, on the device, and are written into that stage's notes; the checker now catches a place wherever it lands.
- **The reviewer set aside that handwriting pictures are not looked inside.** *Why:* Stage 3; noted there that a .png must carry no place.
- **The reviewer set aside whether a clip's sound flag matches its tracks.** *Why:* Spec 6.3 does not ask; left.
- **The reviewer set aside symbolic links in a session folder, a time limit on ExifTool, and checking that an ExifTool found on the PATH is the pinned build.** *Why:* The phone does not make links, and tools/mac-check-session.sh always uses the pinned ExifTool; left.
- **The reviewer set aside timed location tracks inside video.** *Why:* The workbench's import does not read them either; left.
- **The reviewer set aside the wording for a folder from a newer recorder ("version: must be 1").** *Why:* To be reworded when there is a version 2.
- **The reviewer set aside a whole import into a workbench library and Windows.** *Why:* The record says the first was not done; Windows is not a target.

*Left for later:*

- The patch for the workbench carries no test for the workbench's own suite.
- The Mac checks run the Core tests twice (their own step, then inside the build script).
- Spec 6.1's "cleaned the way the workbench cleans" is not literally true (a tab becomes "-" here and a space there); what holds, and is tested, is that the workbench leaves the recorder's folder names unchanged.

## The logic behind the iPhone app (branch `stage-1a`)

- **Started executing without the plan-review handoff.** *Why:* The owner's standing instruction is to proceed as fast as possible with approvals set. *If wrong:* The owner reviews this plan after the fact and asks for changes.
- **A separate worktree, so that work here does not disturb the reviewer who is running tests on the checker branch's checkout.**
- **A note begins at its first character that is not blank space (the plan said its first character).** *Why:* Typing only spaces or a new line never puts an empty note on the page. *If wrong:* A note's time is a moment later than the very first keystroke when the owner begins with a space.
- **The controller does not call a camera. The screen takes a photo in two steps, preparePhoto() at the shutter and photoSaved/photoFailed when the camera has finished, because a real camera answers later, not at once.** *If wrong:* None; the plan's PhotoCapturing protocol can be layered on top.
- **A photo reported after recording has paused is placed on the span that was recording when the shutter was pressed (the timeline now remembers when each span of this run began and ended).** *If wrong:* None seen; before this it would have been placed nowhere, or at the start of the wrong span.
- **An untitled session keeps an empty title in session.json and shows its local date and time ("2026-11-23 10:42") everywhere a title is shown.** *Why:* The plan would have written the date into the title, and the folder name would then say the date twice. *If wrong:* A reader of session.json must apply the same fallback; noted for format/README.md.
- **The session's folder is renamed to match a new title only once nothing is being recorded into it (at the next pause or stop), not at once as the plan said.** *Why:* Renaming a folder while audio and photos are being written into it risks losing them. *If wrong:* Until the next pause the folder keeps its old name; the checker only warns about that.
- **Typing is saved at most every two seconds (a note's first character and everything else are saved at once), not on every keystroke as the plan said.** *If wrong:* Up to two seconds of typing lost if the app is killed.
- **Where the session began is only taken from a location reading that arrives within two minutes of the start.** *If wrong:* A slow first fix leaves the session with no start location; photos still carry their own.
- **Taking a photo after the session was stopped makes it unfinished again (its checksums are cleared) until the next stop; adding a note does not.** *If wrong:* The owner must press stop again after adding a photo before exporting.
- **The recorder now tells the controller the moment its audio really began (AudioRecording.start returns it), and the span starts there.** *Why:* The reviewer pointed out that taking the time after start returns would put every position on the audio out by the start-up delay. *If wrong:* None; a recorder that cannot say returns nil and the old behaviour applies. testTheSpanBeginsWhenTheRecorderSaysItBegan.
- **The earlier ruling that a photo after Stop makes the session unfinished is reversed (see I4).** *If wrong:* None seen.
- **A session started with location off now has a "Location off" line as its second line.** *Why:* It closes the gap the reviewer set aside (a reader could not tell "off from the start" from "no place was available"), and it is what lets a reopened session know. *If wrong:* One extra line at the top of such sessions.
- **Files found on disk but not listed are reported after a crash only, not every time a session is opened.** *Why:* The checker reports them in every case, and a notice on every opening would nag. *If wrong:* A file orphaned while paused is only noticed by the checker.
- **The reviewer set aside open clips at stop and a clip in flight during a rename (stage 2), and handwriting (stage 3).** *Why:* Carried to those stages.
- **The reviewer set aside that a copy made through Files or Finder is never recorded as shared.** *Why:* The app cannot see such a copy; the list says "Not shared yet" only about its own share button; to be worded carefully on the screen in stage 1b.
- **The reviewer set aside that rows carry no date when a session crosses midnight or is added to days later.** *Why:* The spec asks for clock time only; left, and noted for the owner.
- **The reviewer set aside that a session with no media counts as finished while still live.** *Why:* An edge of the format's definition; the app only shares from the list, after stop.
- **The reviewer set aside the wording of "today" and "tomorrow" in the install warning, the 60 s and 120 s limits, and stamping coarse fixes.** *Why:* Design choices; left as built and listed for the owner.
- **The reviewer set aside whether saves survive power loss, the Mac checks running on Intel only, the lower-case "am/pm" form and splitting participants on spaces.** *Why:* Not testable here, infrastructure, or fixed by the plan; left.
- **The reviewer set aside that the controller gives SwiftUI no change notification.** *Why:* Stage 1b wraps it in a model that republishes after every call.

*Left for later:*

- A zero-byte audio file finishes with no notice, though the checker reports it as empty.
- Opening a session that another part of the app is still recording rewrites it as recovered; the list cannot tell a live session from a crashed one.
- A photo reported late is placed correctly on the audio but listed after later items on the page.
- A note left open at a crash keeps its trailing blank space.
- A session folder nested inside another is invisible to the list and is deleted with the outer one; listing 300 long sessions takes about 1.5 s.
- A failed folder rename is silent; a change of capitals only may not rename on a Mac or the simulator (suspected).
- "blank" is decided two slightly different ways in NoteWriter (zero-width space).
- InstallWarning.expiry returns nothing for a date with a fraction or a comment before it.
- The ledger's evidence lines quote the Swift Testing summary line, not the XCTest count.

## The iPhone app's screens (branch `stage-1b`)

This section is written without code names where it can be, because these are the decisions you will see on the phone.

**What the app is at this stage**

- **A red line at the top of every screen says this is a trial version.** The microphone, camera and location are stand-ins, so the app records no sound. The independent reviewer's most serious finding was that nothing on screen said so. *If wrong:* the line is removed in one place when the real hardware goes in.
- **The clock follows the phone's own 12-hour or 24-hour setting.** The plan listed a setting for this inside the app; there is none. *If wrong:* a setting can be added; the wording code already takes either style.
- **Notes are set in the system's serif typeface**, not a bundled one. *If wrong:* a typeface can be bundled later.
- **Dark appearance follows the phone.** The mockups were light only; the dark colours are the same palette turned over. They have been photographed on the hosted Mac but you have not seen or approved them. *If wrong:* the colours are in one file.
- **Text size follows the phone's setting.** Notes grow all the way to the largest size; buttons and bars grow to one and a half times and then stop, so that none is pushed off the screen.

**Writing**

- **The box you type into was rebuilt after review.** The first version put every note on the page twice; its fix then dropped a note that repeated the one before ("Yes." twice). Return now ends a note directly, and the keyboard stays up for the next one.
- **Tapping a note opens it for changing or deleting.** A changed note keeps the time it was first written and is marked "edited". Deleting asks first. The plan had no way to change an older note at all. *If wrong:* the page could instead keep the original and show the change beside it.
- **Pasting several paragraphs makes one note for each.**
- **A new session opens with the keyboard up.** After Hide, and after switching layout, the keyboard comes back if you were writing.
- **The typing box is kept alive on a long page.** The automatic walkthrough found that, once a page was longer than the screen, a new line could push the box out of view for a moment, and the keyboard was then lost. This was not in the review; it would have been met in the first real interview.
- **Participant codes are entered with the title**, by tapping the title. The plan had no way to enter them.

**The two layouts**

- **In the plain layout the controls now sit on a line of their own, above the title.** In the mockup the title and the recorder pill shared a line. With the layout switch and the menu added there was no room for a title, and at large text sizes controls were pushed off the screen. *If wrong:* this is the most visible change from the mockup; say so and it can be laid out differently.
- **In the plain layout the title is the top of the page and scrolls away with it.** Only the controls and the location line stay put. With the keyboard up, a title that stayed put left room for about three lines of notes. *If wrong:* the title can be pinned again; tapping it to change it works either way.
- **The plain layout's pill says "Paused" or "Stopped" in words when it is not recording**, and shows whether location is on under the title. Before, the only sign of a pause was a dot changing from red to grey.
- **The plain layout's three round buttons take their own space at the bottom** instead of floating over the page, so the line being written is never under them.
- **A finished session shows a Close button in both layouts.**

**Hiding**

- **The keyboard shortcut is Command-Shift-B.** The first choice, Command-Shift-H, is the system's own shortcut for the Home Screen.
- **With VoiceOver on, its own double tap brings the page back.**
- **The cover has its own decision record**, `docs/adr/0004-the-cover.md`, as the design asked.

**Location**

- **Switching location on asks first, as switching it off does.** A place written into a photo cannot be taken out afterwards.
- **Opening a session only to read it never changes it.** Before, opening a finished session with the app's location setting off wrote a "Location off" line into it, and the list then said "Changed since it was shared". The line is now written only when something is added (recording starts again, or a photo is taken).

**Safety of what is recorded**

- **A session that was recording when the app was closed is put right as soon as the app opens**, not when you next open that session. It is made complete as it stands, and the list says what was done. It gets no "Stopped" line, because you did not stop it; its page says "Interrupted (the app was closed unexpectedly)". *If wrong:* none seen. You can still open it and carry on recording.
- **Sessions are left out of iCloud and computer backups.** The design said so and asked you to confirm. *If wrong:* a lost or broken phone loses every session that was not shared. Settings says this in words.
- **Pressing Stop stays on the session if it could not be finished**, so the reason is seen.
- **Everything pending is saved when the app leaves the front**, not only on the one-second timer.
- **Every notice is shown until you press OK**, oldest first. Before, a newer notice replaced an older one.
- **Zips made for sharing are removed afterwards**, and at every launch, so copies of sessions do not pile up outside the sessions folder.
- **The switch the automatic walkthrough uses to clear all sessions works only in the simulator.** It cannot be triggered on a real phone.

**How it was checked**

- **Everything is built and walked through on a GitHub-hosted Mac**, because this session cannot compile an iPhone app. The walkthrough is four long walks, not twelve short ones as the plan listed, because each launch takes about a minute there. *If wrong:* an early failure can hide later ones; checks carry on after a failure to limit that.
- **Screenshots are printed into the run's log as text and read back from there**, because this session cannot fetch GitHub's stored files. *If wrong:* about a megabyte of text in each log. They show stand-in content only.
- **Each walkthrough step was written together with its screen and only seen to pass**, not first seen to fail, because each round takes about twenty minutes. The reviewer found several checks that could not fail; those were rewritten (the hidden screen is now checked pixel by pixel, for one).
- **The guide now tells you to use the branch `stage-1b`**, which holds everything so far.

*Left for later:*

- Sharing is not part of the automatic walkthrough; the system's share sheet cannot be driven reliably. To try by hand.
- What the app switcher shows, whether the home indicator hides, and locking while hidden can only be seen on a real phone.
- Making the zip for a long session holds the app up for a moment.
- An untitled session's name uses the 24-hour clock ("2026-11-24 18:23") even when the rows beside it use am and pm.
- The stand-in recorder counts time only while the app is in front, and writes its silent file in one go at each pause. Both go when the real recorder comes in.
- At the very largest text sizes the margin layout leaves only a narrow column for notes; the plain layout reads better there.
- In the margin layout a long title pushes the participant codes off the end of its line. They are still there when the title is tapped.
- A photo is saved as JPEG only on a device that cannot write HEIC at all; a HEIC write that fails for another reason gives a notice, not a JPEG.
