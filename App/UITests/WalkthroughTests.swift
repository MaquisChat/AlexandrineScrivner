import XCTest

/// Drives the app the way a person would, with stand-in hardware, and photographs each screen.
final class WalkthroughTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
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

    private func startSession() {
        app.launch()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 30))
        app.buttons["new-session"].tap()
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 15))
    }

    private func write(_ line: String) {
        let field = element("note-field")
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(line + "\n")
    }

    // MARK: - The walkthrough

    func testTheListStartsEmpty() {
        app.launch()
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["new-session"].exists)
        shot("empty-list")
    }

    func testStartingASession() {
        startSession()
        XCTAssertEqual(element("recorder-state").label, "Recording")
        XCTAssertTrue(text(startingWith: "Recording started").waitForExistence(timeout: 5))
        XCTAssertEqual(element("location-state").label, "Location on")
        shot("untitled-session")
    }

    func testWritingTwoNotes() {
        startSession()
        write("P-014 has run the stall since 2009. Took it over from her aunt, who still does the early shift on Saturdays.")
        write("Prices are handwritten every morning.")
        XCTAssertTrue(text(startingWith: "P-014 has run the stall").waitForExistence(timeout: 5))
        XCTAssertTrue(text(startingWith: "Prices are handwritten").waitForExistence(timeout: 5))
        shot("two-notes")
        describeScreen("two-notes")
        XCTAssertEqual(app.staticTexts.matching(identifier: "note").count, 2)
    }

    func testTakingAPhoto() {
        startSession()
        write("She weighs by eye first and only then uses the scale.")
        app.buttons["photo"].tap()
        XCTAssertTrue(element("photo-row").waitForExistence(timeout: 10))
        write("Asked me not to photograph the ledger.")
        shot("margin-layout")
    }

    func testPauseAndResume() {
        startSession()
        app.buttons["pause-resume"].tap()
        XCTAssertTrue(text(startingWith: "Paused").waitForExistence(timeout: 10))
        XCTAssertEqual(element("recorder-state").label, "Paused")
        write("Off the record: the lease runs out in March.")
        app.buttons["pause-resume"].tap()
        XCTAssertTrue(text(startingWith: "Resumed").waitForExistence(timeout: 10))
        XCTAssertEqual(element("recorder-state").label, "Recording")
        shot("paused-and-resumed")
    }

    func testStopReturnsToTheListWithTheSessionFinished() {
        startSession()
        write("A short session.")
        app.buttons["stop"].tap()
        let confirm = app.buttons["confirm-stop"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertTrue(app.buttons["new-session"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["session-row"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(anything(saying: "Not finished").exists)
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
        shot("list-with-a-session")
    }

    func testSwitchingLayouts() {
        startSession()
        write("P-014 has run the stall since 2009.")
        app.buttons["photo"].tap()
        XCTAssertTrue(element("photo-row").waitForExistence(timeout: 10))
        write("Prices are handwritten every morning.")
        app.buttons["layout-switch"].tap()
        XCTAssertTrue(element("session-title").waitForExistence(timeout: 5))
        XCTAssertTrue(text(startingWith: "P-014 has run the stall").exists)      // the same page, drawn the other way
        XCTAssertTrue(element("photo-row").exists)
        shot("plain-layout")
        app.terminate()
        app.launchArguments = ["-uiTesting"]                                     // the choice is remembered
        app.launch()
        XCTAssertTrue(app.buttons["session-row"].firstMatch.waitForExistence(timeout: 30))
        app.buttons["session-row"].firstMatch.tap()
        XCTAssertTrue(element("layout-switch").waitForExistence(timeout: 15))
        XCTAssertTrue(element("layout-switch").label.hasPrefix("Layout: plain page"))
        app.buttons["layout-switch"].tap()                                       // leave it as the other tests expect
        XCTAssertTrue(element("layout-switch").label.hasPrefix("Layout: times in the margin"))
    }

    func testHideAndReturn() {
        startSession()
        write("Something already on the page.")
        let field = element("note-field")
        field.tap()
        field.typeText("Half a thought")
        app.buttons["hide"].tap()
        let cover = element("cover")
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        XCTAssertFalse(text(startingWith: "Something already").exists)       // nothing of the page can be seen or read out
        shot("hidden")
        cover.tap()                                                              // a single tap does nothing
        XCTAssertTrue(cover.exists)
        cover.doubleTap()
        XCTAssertTrue(element("recorder-state").waitForExistence(timeout: 5))
        XCTAssertFalse(element("cover").exists)
        XCTAssertEqual(element("note-field").value as? String, "Half a thought") // the half-typed note is still there
    }

    func testComingBackAfterBeingClosed() {
        startSession()
        write("Typed before the app was closed.")
        app.terminate()                                                          // swiped away mid-recording
        app.launchArguments = ["-uiTesting"]
        app.launch()
        XCTAssertTrue(app.buttons["session-row"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(anything(saying: "Not finished").exists)
        app.buttons["session-row"].firstMatch.tap()
        XCTAssertTrue(element("notice").waitForExistence(timeout: 15))
        XCTAssertTrue(element("notice").label.hasPrefix("The app was closed while this session was recording"))
        XCTAssertTrue(text(startingWith: "Interrupted (the app was closed unexpectedly)").exists)
        XCTAssertTrue(text(startingWith: "Typed before the app was closed").exists)
        XCTAssertEqual(element("recorder-state").label, "Paused")
        shot("recovered-session")
    }

    func testDeletingASessionAsksFirst() {
        startSession()
        write("A session to delete.")
        app.buttons["stop"].tap()
        app.buttons["confirm-stop"].firstMatch.tap()
        let row = app.buttons["session-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        shot("list-with-sessions")
        row.swipeLeft()
        XCTAssertTrue(app.buttons["delete"].waitForExistence(timeout: 5))
        app.buttons["delete"].tap()
        let confirm = app.buttons["confirm-delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))                      // nothing is deleted without being asked
        XCTAssertTrue(row.exists)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 10))
    }

    func testSettingsTurnLocationOffForNewSessions() {
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 30))
        app.buttons["settings"].tap()
        let toggle = app.switches["location-default"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertEqual(toggle.value as? String, "1")                             // on when the app is first installed
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        shot("settings")
        app.buttons["settings-done"].tap()
        app.buttons["new-session"].tap()
        XCTAssertTrue(element("location-state").waitForExistence(timeout: 15))
        XCTAssertEqual(element("location-state").label, "Location off")
    }

    /// Runs last (tests run in name order) and leaves one finished session behind, which
    /// tools/mac-walkthrough.sh copies out of the simulator and gives to the session checker.
    func testZZTheSessionLeftForTheChecker() {
        app.launchArguments = ["-uiTesting", "-resetSessions", "-uiTestingLocation"]
        startSession()
        write("P-014 has run the stall since 2009.")
        app.buttons["photo"].tap()
        XCTAssertTrue(element("photo-row").waitForExistence(timeout: 10))
        app.buttons["pause-resume"].tap()
        XCTAssertTrue(text(startingWith: "Paused").waitForExistence(timeout: 10))
        write("Off the record: the lease runs out in March.")
        app.buttons["pause-resume"].tap()
        XCTAssertTrue(text(startingWith: "Resumed").waitForExistence(timeout: 10))
        app.buttons["photo"].tap()
        write("Asked me not to photograph the ledger.")
        app.buttons["stop"].tap()
        app.buttons["confirm-stop"].firstMatch.tap()
        XCTAssertTrue(app.buttons["session-row"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(anything(saying: "Not shared yet").exists)
    }
}
