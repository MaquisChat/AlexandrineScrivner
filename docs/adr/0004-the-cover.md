# 0004. The cover that hides the page

- **Status:** Accepted
- **Date:** 2026-11-24

## Context

The owner asked for a button that hides the app quickly while recording carries on, and said: a blank screen for now, with provision for putting other things there later (design spec, section 5.6).

So two things had to be decided: how hiding works today, and how a different cover could be added later without touching recording or the page.

## Decision

1. **A cover is a small, separate part.** In the code it is the `Cover` protocol in `App/Sources/Cover.swift`. A cover supplies two things only: what is drawn while the page is hidden, and what brings the page back. It is handed one thing: a `dismiss` action to call when the page should return.

2. **A cover knows nothing about the session.** It is not given the notes, the recorder or the list of photos, so a cover cannot show any of them by mistake, and nothing a cover does can stop or disturb a recording. Recording and the page do not know which cover is in use, or that there is one.

3. **This version ships one cover, `BlankCover`:** the whole screen black. A single tap does nothing. A double tap anywhere brings the page back. With VoiceOver on, the cover is announced as "Hidden", and VoiceOver's own double tap brings the page back.

4. **The session screen does the hiding, the same way for every cover.** When the page is hidden, the session screen:
   - puts the keyboard away, so that typing goes nowhere;
   - stops the page from taking touches and hides it from VoiceOver;
   - hides the status bar and, as far as iOS allows, the home indicator;
   - draws the cover over everything.

   When the page comes back, the keyboard returns if the owner was writing when it was hidden.

5. **Three ways to hide and return.** The Hide button in either layout; a double tap on the cover to return; and, with a keyboard attached, Command-Shift-B for both. That shortcut was chosen because iOS and iPadOS do not use it; the first choice, Command-Shift-H, is the system's own shortcut for the Home Screen.

6. **The app switcher never shows the page.** Whenever the app is not in front, the page is covered in black, whether or not the owner had pressed Hide. This is separate from the cover: it is always the plain black shade, whatever cover is in use.

7. **The cover does not hide the recording from iOS.** iOS shows its own indicator while the microphone is in use. The app does not try to hide it and must never claim that it can.

## Consequences

- Adding another cover later means writing one new type that draws something and decides what dismisses it, then choosing it where the session screen now says `BlankCover()`. Nothing in recording, saving or the page changes. A setting to choose between covers would be added at that point; with one cover there is nothing to choose.
- Because a cover receives nothing about the session, a cover that wanted to show, say, the elapsed time would need this decision revisited. That is deliberate: the safe default is that a cover can show nothing.
- A cover that wanted a different way back (a long press, a pattern) can have one, since each cover decides its own. The keyboard shortcut works with every cover, because it belongs to the session screen.
- The automatic walkthrough checks the blank cover two ways: that nothing of the page can be read out, and that the screenshot taken while hidden is black in every pixel.
- Still to check on a real phone, because the simulator cannot show them: that the home indicator hides, what the app switcher shows, and that the screen dims and locks as normal while covered.
