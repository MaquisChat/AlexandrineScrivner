import UIKit
import XCTest

/// Drives the app the way a person would, with stand-in hardware, and photographs each screen.
///
/// Four walks, run in name order. The third leaves a finished session behind, which
/// tools/mac-walkthrough.sh copies out of the simulator and gives to the session checker.
/// The simulator on a hosted Mac is slow, so waits are generous and typed lines are short.
final class WalkthroughTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        // One failed check should not hide what the rest of a long walk would have shown.
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetSessions"]
    }

    // MARK: - Helpers

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// True when the whole screen is black, pixel for pixel: the cover must show nothing at all.
    private func screenIsEntirelyBlack() -> Bool {
        guard let picture = XCUIScreen.main.screenshot().image.cgImage else { return false }
        let width = 90, height = 195
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        for index in stride(from: 0, to: pixels.count, by: 4)
        where pixels[index] > 10 || pixels[index + 1] > 10 || pixels[index + 2] > 10 {
            return false
        }
        return true
    }

    /// Keeps a text description of everything on screen, for working out a failure afterwards.
    private func describeScreen(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "screen-" + name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Everything with this identifier whose words begin a certain way.
    private func all(_ identifier: String, startingWith prefix: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
    }

    /// A line the recorder wrote on the page itself: "Recording started", "Paused" and so on.
    private func marker(_ prefix: String) -> XCUIElement {
        all("marker", startingWith: prefix).firstMatch
    }

    /// A note on the page.
    private func note(_ prefix: String) -> XCUIElement {
        all("note", startingWith: prefix).firstMatch
    }

    /// Any element whose label contains the words, however the system has grouped it.
    private func anything(saying words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    /// What the recorder says it is doing, in lower case ("recording", "paused", "stopped").
    /// The margin layout says it in words of its own; the plain layout says it on its pill.
    private var recorderState: String {
        let word = element("recorder-state")
        if word.exists {
            return word.label.lowercased()
        }
        let pause = button("pause-resume")
        let pill = pause.exists ? ((pause.value as? String) ?? "") : ""
        return (pill.components(separatedBy: ",").first ?? "").lowercased()
    }

    private func hasKeyboard(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// Waits for a text box to have the keyboard without being tapped.
    private func takesKeyboard(_ identifier: String, within seconds: TimeInterval = 20) -> Bool {
        let field = element(identifier)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if field.exists && hasKeyboard(field) {
                dismissKeyboardTip()
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func noteFieldTakesKeyboard() -> Bool {
        takesKeyboard("note-field")
    }

    /// A fresh simulator covers its keyboard with a tip about sliding to type, the first time.
    private func dismissKeyboardTip() {
        let button = app.buttons["Continue"].firstMatch
        if button.exists {
            button.tap()
            // Keys typed while the keyboard is still settling can be lost.
            Thread.sleep(forTimeInterval: 3)
        }
    }

    /// A button, by its identifier or its words. Always the first match: the system sometimes
    /// lists one button twice (an alert's, for one), and asking to tap "the" button then fails.
    private func button(_ name: String) -> XCUIElement {
        app.buttons[name].firstMatch
    }

    /// Taps something once it is there. If it never appears, that is a failure, and the walk
    /// carries on, so that one missing control does not hide everything after it.
    @discardableResult
    private func press(_ element: XCUIElement, _ what: String, within seconds: TimeInterval = 30,
                       byPosition: Bool = false) -> Bool {
        guard element.waitForExistence(timeout: seconds) else {
            XCTFail("\(what) was not there to be tapped")
            describeScreen("missing-" + what.replacingOccurrences(of: " ", with: "-"))
            return false
        }
        if byPosition {
            // For an item in a menu: the simulator cannot say where such an item should be
            // touched, though it knows where it is. Its middle is touched instead.
            let place = element.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: place.midX, dy: place.midY)).tap()
        } else {
            element.tap()
        }
        return true
    }

    /// What is in the note field just now, or nothing if the field is not there.
    private var typedSoFar: String {
        let field = element("note-field")
        return field.exists ? ((field.value as? String) ?? "") : ""
    }

    /// The words of an element, or nothing if it is not there. (Asking a missing element for its
    /// words ends the whole walk.)
    private func words(_ element: XCUIElement) -> String {
        element.exists ? element.label : ""
    }

    /// The note field should have the keyboard already. If it has not, that is a failure, and the
    /// field is tapped so that the rest of the walk still means something.
    private func expectKeyboard(_ why: String) {
        if !noteFieldTakesKeyboard() {
            XCTFail(why)
            element("note-field").tap()
        }
    }

    private func launch() {
        app.launch()
        XCTAssertTrue(button("new-session").waitForExistence(timeout: 120), "the list did not appear")
    }

    private func startSession() {
        button("new-session").tap()
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 120), "the session did not open")
    }

    private func write(_ line: String) {
        let field = element("note-field")
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        field.tap()
        dismissKeyboardTip()
        field.typeText(line + "\n")
        if !note(line).waitForExistence(timeout: 30) {
            XCTFail("\"\(line)\" did not reach the page")
            describeScreen("did-not-reach-the-page")
            shot("did-not-reach-the-page")
        }
    }

    private func stopSession() {
        button("stop").tap()
        let confirm = button("confirm-stop")
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.tap()
        XCTAssertTrue(button("new-session").waitForExistence(timeout: 60), "stopping did not return to the list")
    }

    // MARK: - The walks

    /// The list when empty, settings, and a session started with location off; then deleting it.
    func test1ListSettingsAndDeleting() {
        launch()
        XCTAssertTrue(app.staticTexts["No sessions yet"].exists)
        XCTAssertTrue(element("trial-banner").exists, "the list says this version records nothing real")
        shot("empty-list")

        press(button("settings"), "settings")
        let toggle = app.switches["location-default"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 30))
        XCTAssertEqual(toggle.value as? String, "1", "location should be on when the app is first installed")
        if toggle.switches.firstMatch.exists {
            toggle.switches.firstMatch.tap()
        } else {
            toggle.tap()
        }
        XCTAssertEqual(toggle.value as? String, "0")
        shot("settings")
        press(button("settings-done"), "settings-done")

        startSession()
        XCTAssertEqual(recorderState, "recording")
        XCTAssertTrue(element("trial-banner").exists, "the session says this version records nothing real")
        XCTAssertEqual(words(element("location-state")), "Location off")
        XCTAssertTrue(marker("Recording started").waitForExistence(timeout: 30))
        XCTAssertTrue(marker("Location off").exists, "a session started with location off says so on its page")
        XCTAssertTrue(noteFieldTakesKeyboard(), "a new session opens ready to be typed into")
        shot("untitled-session")
        write("A short session.")
        stopSession()

        let row = button("session-row")
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertFalse(anything(saying: "Not finished").exists)
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
        shot("list-with-a-session")
        row.swipeLeft()
        XCTAssertTrue(button("delete").waitForExistence(timeout: 15))
        press(button("delete"), "delete")
        let confirm = button("confirm-delete")
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "nothing is deleted without being asked")
        XCTAssertTrue(row.exists)
        press(confirm, "the confirmation")
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 30))
    }

    /// The app is closed mid-recording and opened again: the session is put right at once, the
    /// list says so, and the session can be read, added to and stopped.
    func test2ComingBackAfterBeingClosed() {
        launch()
        startSession()
        write("Typed before closing.")
        app.terminate()                                                          // swiped away mid-recording
        app.launchArguments = ["-uiTesting"]
        launch()

        let notice = element("launch-notice")
        XCTAssertTrue(notice.waitForExistence(timeout: 60), "the list says what was put right")
        XCTAssertTrue(words(notice).contains("was still recording when the app was last closed"))
        XCTAssertTrue(button("session-row").waitForExistence(timeout: 60))
        XCTAssertFalse(anything(saying: "Not finished").exists, "the session is complete without being opened")
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
        shot("list-after-being-closed")
        press(button("dismiss-launch-notice"), "dismiss-launch-notice")
        XCTAssertFalse(element("launch-notice").exists)

        press(button("session-row"), "session-row")
        XCTAssertTrue(marker("Interrupted (the app was closed unexpectedly)").waitForExistence(timeout: 60))
        XCTAssertTrue(note("Typed before closing").exists)
        XCTAssertEqual(recorderState, "paused")
        shot("recovered-session")

        // It can be carried on with, and stopped properly this time.
        press(button("pause-resume"), "pause-resume")
        XCTAssertTrue(marker("Resumed").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "recording")
        write("Typed after coming back.")
        stopSession()
        XCTAssertFalse(anything(saying: "Not finished").exists)
    }

    /// A whole session: notes, editing, photos, location, pause and resume, both layouts, hiding, and stop.
    func test3AWholeSession() {
        app.launchArguments = ["-uiTesting", "-resetSessions", "-uiTestingLocation"]
        launch()
        startSession()
        XCTAssertEqual(recorderState, "recording")
        XCTAssertEqual(words(element("location-state")), "Location on")

        // Two notes typed straight off, Return between them, without touching the screen.
        let field = element("note-field")
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        expectKeyboard("a new session opens ready to be typed into")
        app.typeText("Stall since 2009.\nPrices by hand.\n")
        XCTAssertTrue(note("Prices by hand").waitForExistence(timeout: 30))
        XCTAssertEqual(all("note", startingWith: "Stall since 2009").count, 1, "each note is on the page once")
        XCTAssertEqual(all("note", startingWith: "Prices by hand").count, 1)

        // The same words twice are two notes.
        app.typeText("Yes.\nYes.\n")
        XCTAssertTrue(note("Yes.").waitForExistence(timeout: 30))
        XCTAssertEqual(all("note", startingWith: "Yes.").count, 2, "a repeated note is kept, not dropped")
        describeScreen("four-notes")

        // An older note is changed: it opens with the cursor at its end, keeps its place, and is
        // marked as edited.
        press(note("Prices by hand"), "Prices by hand")
        let editor = element("note-editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        if !takesKeyboard("note-editor") {
            XCTFail("a note opened for changing is ready to be typed into")
            press(editor, "note-editor")
        }
        app.typeText(" Always.")
        shot("editing-a-note")
        press(button("save-note"), "save-note")
        let changed = note("Prices by hand. Always.")
        XCTAssertTrue(changed.waitForExistence(timeout: 30), "the change did not reach the page, at the end of the note")
        XCTAssertTrue(words(changed).contains("edited"), "a changed note says it was edited")

        // And one is deleted, after being asked.
        press(note("Yes."), "Yes.")
        XCTAssertTrue(button("delete-note").waitForExistence(timeout: 30))
        press(button("delete-note"), "delete-note")
        let confirmDelete = button("confirm-delete-note")
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 30), "no note is deleted without being asked")
        press(confirmDelete, "confirm-delete-note")
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 30))
        XCTAssertEqual(all("note", startingWith: "Yes.").count, 1)

        // Title and participants.
        press(element("session-title"), "session-title")
        let title = app.textFields["title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        press(title, "title-field")
        title.typeText("Market stall holders, second visit")
        let who = app.textFields["participants-field"]
        press(who, "participants-field")
        who.typeText("P-014")
        press(button("details-save"), "details-save")
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 30))
        XCTAssertTrue(words(element("session-title")).contains("Market stall"))
        XCTAssertTrue(words(element("session-title")).contains("P-014"))

        // A photo with location on; then location off, which asks first, and a photo without.
        press(button("photo"), "photo")
        XCTAssertTrue(element("photo-row").waitForExistence(timeout: 30))
        press(element("location-state"), "location-state")
        let turnOff = app.alerts.buttons["Turn off"].firstMatch
        XCTAssertTrue(turnOff.waitForExistence(timeout: 30), "location is not switched without being asked")
        XCTAssertEqual(words(element("location-state")), "Location on")
        press(turnOff, "Turn off")
        XCTAssertTrue(marker("Location off").waitForExistence(timeout: 30))
        XCTAssertEqual(words(element("location-state")), "Location off")
        press(button("photo"), "photo")

        press(button("pause-resume"), "pause-resume")
        XCTAssertTrue(marker("Paused").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "paused")
        write("Off the record.")
        press(button("pause-resume"), "pause-resume")
        XCTAssertTrue(marker("Resumed").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "recording")
        XCTAssertFalse(element("notice").exists, "nothing went wrong along the way")
        XCTAssertTrue(noteFieldTakesKeyboard(), "the keyboard stays up when a line is added to a page longer than the screen")
        shot("margin-layout")

        // The same page, drawn the other way, with the keyboard carried over.
        press(button("layout-switch"), "layout-switch")
        XCTAssertTrue(words(element("layout-switch")).hasPrefix("Layout: plain page"))
        XCTAssertTrue(note("Off the record").waitForExistence(timeout: 30))
        XCTAssertEqual(recorderState, "recording")
        XCTAssertEqual(words(element("location-state")), "Location off", "the plain layout says whether location is on")
        expectKeyboard("switching layout while writing keeps the keyboard")
        shot("plain-layout")

        // Hide while half way through a note.
        app.typeText("Half a thought")
        XCTAssertTrue(button("hide").isHittable, "Hide can be reached while writing")
        shot("plain-layout-writing")
        press(button("hide"), "hide")
        let cover = element("cover")
        if cover.waitForExistence(timeout: 15) {
            XCTAssertFalse(note("Off the record").exists, "nothing of the page can be read out")
            XCTAssertTrue(screenIsEntirelyBlack(), "nothing of the page can be seen")
            shot("hidden")
            cover.tap()                                                          // a single tap does nothing
            XCTAssertTrue(cover.exists)
            cover.doubleTap()
        } else {
            XCTFail("Hide did not cover the page")
        }
        XCTAssertTrue(button("hide").waitForExistence(timeout: 15))
        XCTAssertFalse(element("cover").exists)
        XCTAssertEqual(typedSoFar, "Half a thought", "the half-typed note is still there")
        expectKeyboard("coming back from the cover carries on where the writing was")
        app.typeText(", finished.")
        XCTAssertEqual(typedSoFar, "Half a thought, finished.")

        // The same from an attached keyboard: Command-Shift-B hides, and brings the page back.
        app.typeKey("b", modifierFlags: [.command, .shift])
        if cover.waitForExistence(timeout: 15) {
            XCTAssertTrue(screenIsEntirelyBlack())
            app.typeKey("b", modifierFlags: [.command, .shift])
            XCTAssertTrue(button("hide").waitForExistence(timeout: 15))
            XCTAssertFalse(element("cover").exists, "the shortcut brings the page back")
        } else {
            XCTFail("Command-Shift-B did not hide the page")
        }

        // Paused, seen on the plain layout.
        press(button("pause-resume"), "pause-resume")
        XCTAssertTrue(marker("Paused").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "paused")
        shot("plain-layout-paused")
        press(button("pause-resume"), "pause-resume")
        XCTAssertEqual(recorderState, "recording")

        // Stopped from the plain layout, where Stop is in the menu. The layout stays as chosen.
        press(button("session-menu"), "session-menu")
        let stop = button("Stop session")
        XCTAssertTrue(stop.waitForExistence(timeout: 30))
        shot("plain-layout-menu")
        press(stop, "Stop session", byPosition: true)
        let confirmStop = button("confirm-stop")
        XCTAssertTrue(confirmStop.waitForExistence(timeout: 30))
        press(confirmStop, "confirm-stop")
        XCTAssertTrue(button("new-session").waitForExistence(timeout: 60), "stopping did not return to the list")
        XCTAssertTrue(button("session-row").waitForExistence(timeout: 30))
        XCTAssertTrue(anything(saying: "Market stall").exists)
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
        shot("list-after-a-whole-session")
    }

    /// The session the last walk left, read again in the dark appearance with the phone's text
    /// size at its very largest, in both layouts. The layout chosen in the last walk is still the
    /// one shown. It only looks: the session is left exactly as it was, for the checker.
    func test4LargestTextInTheDark() {
        app.launchArguments = ["-uiTesting", "-uiTestingDark",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch()
        let row = button("session-row")
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        shot("largest-text-list")
        press(row, "the session in the list")
        XCTAssertTrue(button("pause-resume").waitForExistence(timeout: 60))
        XCTAssertTrue(words(element("layout-switch")).hasPrefix("Layout: plain page"), "the layout is remembered between launches")
        XCTAssertEqual(recorderState, "stopped")
        for control in ["photo", "hide", "pause-resume", "layout-switch", "close", "session-menu", "location-state"] {
            XCTAssertTrue(app.buttons[control].isHittable, "\(control) is pushed off the screen in the plain layout")
        }
        shot("largest-text-plain")

        press(button("layout-switch"), "layout-switch")
        XCTAssertTrue(words(element("layout-switch")).hasPrefix("Layout: times in the margin"))
        XCTAssertEqual(recorderState, "stopped")
        for control in ["photo", "hide", "pause-resume", "layout-switch", "close", "location-state", "session-title"] {
            XCTAssertTrue(app.buttons[control].isHittable, "\(control) is pushed off the screen in the margin layout")
        }
        shot("largest-text-margin")

        press(button("close"), "close")
        XCTAssertTrue(button("new-session").waitForExistence(timeout: 60))
    }
}
