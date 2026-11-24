import XCTest

/// Drives the app the way a person would, with stand-in hardware, and photographs each screen.
///
/// Three walks, run in name order. The last one leaves a finished session behind, which
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

    private func text(startingWith prefix: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Any element whose label contains the words, however the system has grouped it.
    private func anything(saying words: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", words)).firstMatch
    }

    /// What the recorder bar says, in lower case ("recording", "paused", "stopped").
    private var recorderState: String {
        element("recorder-state").label.lowercased()
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
        XCTAssertTrue(text(startingWith: line).waitForExistence(timeout: 30), "\"\(line)\" did not reach the page")
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
        XCTAssertEqual(element("location-state").label, "Location off")
        XCTAssertTrue(text(startingWith: "Recording started").waitForExistence(timeout: 30))
        XCTAssertTrue(text(startingWith: "Location off").exists, "a session started with location off says so on its page")
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

    /// The app is closed mid-recording and opened again.
    func test2ComingBackAfterBeingClosed() {
        launch()
        startSession()
        write("Typed before closing.")
        app.terminate()                                                          // swiped away mid-recording
        app.launchArguments = ["-uiTesting"]
        launch()
        XCTAssertTrue(app.buttons["session-row"].firstMatch.waitForExistence(timeout: 60))
        XCTAssertTrue(anything(saying: "Not finished").exists)
        app.buttons["session-row"].firstMatch.tap()
        XCTAssertTrue(element("notice").waitForExistence(timeout: 60))
        XCTAssertTrue(element("notice").label.hasPrefix("The app was closed while this session was recording"))
        XCTAssertTrue(text(startingWith: "Interrupted (the app was closed unexpectedly)").exists)
        XCTAssertTrue(text(startingWith: "Typed before closing").exists)
        XCTAssertEqual(recorderState, "paused")
        shot("recovered-session")
    }

    /// A whole session: notes, photos, pause and resume, both layouts, hiding, and stop.
    func test3AWholeSession() {
        app.launchArguments = ["-uiTesting", "-resetSessions", "-uiTestingLocation"]
        launch()
        startSession()
        XCTAssertEqual(recorderState, "recording")
        XCTAssertEqual(element("location-state").label, "Location on")

        write("Stall since 2009.")
        write("Prices by hand.")
        describeScreen("two-notes")
        XCTAssertEqual(app.staticTexts.matching(identifier: "note").count, 2, "each note is on the page once")

        app.buttons["photo"].tap()
        XCTAssertTrue(element("photo-row").waitForExistence(timeout: 30))

        app.buttons["pause-resume"].tap()
        XCTAssertTrue(text(startingWith: "Paused").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "paused")
        write("Off the record.")
        app.buttons["pause-resume"].tap()
        XCTAssertTrue(text(startingWith: "Resumed").waitForExistence(timeout: 60))
        XCTAssertEqual(recorderState, "recording")
        shot("margin-layout")

        // The same page, drawn the other way; then back.
        app.buttons["layout-switch"].tap()
        XCTAssertTrue(element("layout-switch").label.hasPrefix("Layout: plain page"))
        XCTAssertTrue(text(startingWith: "Stall since 2009").exists)
        XCTAssertTrue(element("photo-row").exists)
        shot("plain-layout")
        app.buttons["layout-switch"].tap()
        XCTAssertTrue(element("layout-switch").label.hasPrefix("Layout: times in the margin"))

        // Hide while half way through a note.
        let field = element("note-field")
        field.tap()
        field.typeText("Half a thought")
        app.buttons["hide"].tap()
        let cover = element("cover")
        XCTAssertTrue(cover.waitForExistence(timeout: 15))
        XCTAssertFalse(text(startingWith: "Stall since 2009").exists, "nothing of the page can be seen or read out")
        shot("hidden")
        cover.tap()                                                              // a single tap does nothing
        XCTAssertTrue(cover.exists)
        cover.doubleTap()
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 15))
        XCTAssertFalse(element("cover").exists)
        XCTAssertEqual(element("note-field").value as? String, "Half a thought", "the half-typed note is still there")

        stopSession()
        XCTAssertTrue(app.buttons["session-row"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
        shot("list-after-a-whole-session")
    }
}
