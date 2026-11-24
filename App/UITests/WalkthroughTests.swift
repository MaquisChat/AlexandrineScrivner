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
        XCTAssertEqual(app.staticTexts.matching(identifier: "note").count, 2)
        shot("two-notes")
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
}
