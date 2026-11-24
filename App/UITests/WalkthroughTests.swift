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

    override func tearDown() {
        // The last walk turns the simulator dark; leave it as it was found.
        XCUIDevice.shared.appearance = .light
    }

    // MARK: - Helpers

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        let pill = (app.buttons["pause-resume"].value as? String) ?? ""
        return (pill.components(separatedBy: ",").first ?? "").lowercased()
    }

    private func hasKeyboard(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// Waits for the note field to have the keyboard without being tapped.
    private func noteFieldTakesKeyboard(within seconds: TimeInterval = 20) -> Bool {
        let field = element("note-field")
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if field.exists && hasKeyboard(field) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
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
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 120), "the list did not appear")
    }

    private func startSession() {
        app.buttons["new-session"].tap()
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 120), "the session did not open")
    }

    private func write(_ line: String) {
        let field = element("note-field")
        XCTAssertTrue(field.waitForExistence(timeout: 30))
        field.tap()
        field.typeText(line + "\n")
        XCTAssertTrue(note(line).waitForExistence(timeout: 30), "\"\(line)\" did not reach the page")
    }

    private func stopSession() {
        app.buttons["stop"].tap()
        let confirm = app.buttons["confirm-stop"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.tap()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 60), "stopping did not return to the list")
    }

    // MARK: - The walks

    /// The list when empty, settings, and a session started with location off; then deleting it.
    func test1ListSettingsAndDeleting() {
        launch()
        XCTAssertTrue(app.staticTexts["No sessions yet"].exists)
        XCTAssertTrue(element("trial-banner").exists, "the list says this version records nothing real")
        shot("empty-list")

        app.buttons["settings"].tap()
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
        app.buttons["settings-done"].tap()

        startSession()
        XCTAssertEqual(recorderState, "recording")
        XCTAssertTrue(element("trial-banner").exists, "the session says this version records nothing real")
        XCTAssertEqual(element("location-state").label, "Location off")
        XCTAssertTrue(marker("Recording started").waitForExistence(timeout: 30))
        XCTAssertTrue(marker("Location off").exists, "a session started with location off says so on its page")
        XCTAssertTrue(noteFieldTakesKeyboard(), "a new session opens ready to be typed into")
        shot("untitled-session")
        write("A short session.")
        stopSession()

        let row = app.buttons["session-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        XCTAssertFalse(anything(saying: "Not finished").exists)
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
        shot("list-with-a-session")
        row.swipeLeft()
        XCTAssertTrue(app.buttons["delete"].waitForExistence(timeout: 15))
        app.buttons["delete"].tap()
        let confirm = app.buttons["confirm-delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 15), "nothing is deleted without being asked")
        XCTAssertTrue(row.exists)
        confirm.tap()
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
        XCTAssertTrue(notice.label.contains("was still recording when the app was last closed"))
        XCTAssertTrue(app.buttons["session-row"].firstMatch.waitForExistence(timeout: 60))
        XCTAssertFalse(anything(saying: "Not finished").exists, "the session is complete without being opened")
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
        shot("list-after-being-closed")
        app.buttons["dismiss-launch-notice"].tap()
        XCTAssertFalse(element("launch-notice").exists)

        app.buttons["session-row"].firstMatch.tap()
        XCTAssertTrue(marker("Interrupted (the app was closed unexpectedly)").waitForExistence(timeout: 60))
        XCTAssertTrue(note("Typed before closing").exists)
        XCTAssertEqual(recorderState, "paused")
        shot("recovered-session")

        // It can be carried on with, and stopped properly this time.
        app.buttons["pause-resume"].tap()
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
        XCTAssertEqual(element("location-state").label, "Location on")

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

        // An older note is changed: it keeps its place and is marked as edited.
        note("Prices by hand").tap()
        let editor = element("note-editor")
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        editor.tap()
        editor.typeText(" Always.")
        shot("editing-a-note")
        app.buttons["save-note"].tap()
        let changed = all("note", startingWith: "Prices by hand").matching(NSPredicate(format: "label CONTAINS %@", "Always.")).firstMatch
        XCTAssertTrue(changed.waitForExistence(timeout: 30), "the change did not reach the page")
        XCTAssertTrue(changed.label.contains("edited"), "a changed note says it was edited")

        // And one is deleted, after being asked.
        note("Yes.").tap()
        XCTAssertTrue(app.buttons["delete-note"].waitForExistence(timeout: 30))
        app.buttons["delete-note"].tap()
        let confirmDelete = app.buttons["confirm-delete-note"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 30), "no note is deleted without being asked")
        confirmDelete.tap()
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 30))
        XCTAssertEqual(all("note", startingWith: "Yes.").count, 1)

        // Title and participants.
        element("session-title").tap()
        let title = app.textFields["title-field"]
        XCTAssertTrue(title.waitForExistence(timeout: 30))
        title.tap()
        title.typeText("Market stall")
        let who = app.textFields["participants-field"]
        who.tap()
        who.typeText("P-014")
        app.buttons["details-save"].tap()
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 30))
        XCTAssertTrue(element("session-title").label.contains("Market stall"))
        XCTAssertTrue(element("session-title").label.contains("P-014"))

        // A photo with location on; then location off, which asks first, and a photo without.
        app.buttons["photo"].tap()
        XCTAssertTrue(element("photo-row").waitForExistence(timeout: 30))
        element("location-state").tap()
        let turnOff = app.alerts.buttons["Turn off"]
        XCTAssertTrue(turnOff.waitForExistence(timeout: 30), "location is not switched without being asked")
        XCTAssertEqual(element("location-state").label, "Location on")
        turnOff.tap()
        XCTAssertTrue(marker("Location off").waitForExistence(timeout: 30))
        XCTAssertEqual(element("location-state").label, "Location off")
        app.buttons["photo"].tap()

        app.buttons["pause-resume"].tap()
        XCTAssertTrue(marker("Paused").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "paused")
        write("Off the record.")
        app.buttons["pause-resume"].tap()
        XCTAssertTrue(marker("Resumed").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "recording")
        XCTAssertFalse(element("notice").exists, "nothing went wrong along the way")
        shot("margin-layout")

        // The same page, drawn the other way, with the keyboard carried over.
        app.buttons["layout-switch"].tap()
        XCTAssertTrue(element("layout-switch").label.hasPrefix("Layout: plain page"))
        XCTAssertTrue(note("Off the record").waitForExistence(timeout: 30))
        XCTAssertEqual(recorderState, "recording")
        XCTAssertEqual(element("location-state").label, "Location off", "the plain layout says whether location is on")
        expectKeyboard("switching layout while writing keeps the keyboard")
        shot("plain-layout")

        // Hide while half way through a note.
        app.typeText("Half a thought")
        XCTAssertTrue(app.buttons["hide"].isHittable, "Hide can be reached while writing")
        shot("plain-layout-writing")
        app.buttons["hide"].tap()
        let cover = element("cover")
        XCTAssertTrue(cover.waitForExistence(timeout: 15))
        XCTAssertFalse(note("Off the record").exists, "nothing of the page can be seen or read out")
        shot("hidden")
        cover.tap()                                                              // a single tap does nothing
        XCTAssertTrue(cover.exists)
        cover.doubleTap()
        XCTAssertTrue(app.buttons["hide"].waitForExistence(timeout: 15))
        XCTAssertFalse(element("cover").exists)
        XCTAssertEqual(element("note-field").value as? String, "Half a thought", "the half-typed note is still there")
        expectKeyboard("coming back from the cover carries on where the writing was")
        app.typeText(", finished.")
        XCTAssertEqual(element("note-field").value as? String, "Half a thought, finished.")

        // Paused, seen on the plain layout.
        app.buttons["pause-resume"].tap()
        XCTAssertTrue(marker("Paused").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "paused")
        shot("plain-layout-paused")
        app.buttons["pause-resume"].tap()
        XCTAssertEqual(recorderState, "recording")

        app.buttons["layout-switch"].tap()
        XCTAssertTrue(element("layout-switch").label.hasPrefix("Layout: times in the margin"))
        stopSession()
        XCTAssertTrue(app.buttons["session-row"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(anything(saying: "Market stall").exists)
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
        shot("list-after-a-whole-session")
    }

    /// The session the last walk left, read again in the dark appearance with the phone's text
    /// size at its very largest, in both layouts. It only looks: the session is left exactly as
    /// it was, for the checker.
    func test4LargestTextInTheDark() {
        XCUIDevice.shared.appearance = .dark
        app.launchArguments = ["-uiTesting", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        launch()
        let row = app.buttons["session-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 60))
        shot("largest-text-list")
        row.tap()
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "stopped")
        for control in ["photo", "hide", "pause-resume", "layout-switch", "close", "location-state"] {
            XCTAssertTrue(app.buttons[control].isHittable, "\(control) is pushed off the screen in the margin layout")
        }
        shot("largest-text-margin")

        app.buttons["layout-switch"].tap()
        XCTAssertTrue(element("layout-switch").label.hasPrefix("Layout: plain page"))
        XCTAssertEqual(recorderState, "stopped")
        for control in ["photo", "hide", "pause-resume", "layout-switch", "close", "session-menu"] {
            XCTAssertTrue(app.buttons[control].isHittable, "\(control) is pushed off the screen in the plain layout")
        }
        shot("largest-text-plain")
        app.buttons["layout-switch"].tap()
        XCTAssertTrue(element("layout-switch").label.hasPrefix("Layout: times in the margin"))

        app.buttons["close"].tap()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 60))
    }
}
