import XCTest

// The SDK in an app built with UIKit, with a sign-in screen that gives way to tabs by
// changing the window's root. Start Example/TestServer first.

final class UIKitHostTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(bot: String = "live-bot", inset: Int? = nil, openAtLaunch: Bool = false, environment: [String: String] = [:]) {
        app = XCUIApplication()
        app.launchEnvironment["CHATFROM_BASE_URL"] = "http://localhost:4599"
        app.launchEnvironment["CHATFROM_BOT"] = bot
        app.launchEnvironment.merge(environment) { _, new in new }
        if let inset { app.launchEnvironment["CHATFROM_INSET"] = String(inset) }
        if openAtLaunch { app.launchEnvironment["CHATFROM_OPEN_AT_LAUNCH"] = "1" }
        app.launch()
    }

    private func tapRow(_ title: String) {
        let row = app.staticTexts[title]
        if !row.isHittable { app.swipeUp() }
        row.tap()
    }

    private var web: XCUIElement { app.webViews.firstMatch }

    private func expectLog(_ start: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", start)).firstMatch.waitForExistence(timeout: timeout), "the page never said: \(start)\nIt says: \(web.staticTexts.allElementsBoundByIndex.map(\.label))", file: file, line: line)
    }

    /// There, and something is over it.
    private func expectCovered(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.exists, "\(element) is gone, not covered", file: file, line: line)
        XCTAssertFalse(element.isHittable, "\(element) is on top", file: file, line: line)
    }

    private func shot(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["CHATFROM_SHOTS"] else { return }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/uikit-\(device)-\(name).png"))
    }

    private var bubble: XCUIElement { app.buttons["chatfrom.bubble"] }
    private var closeButton: XCUIElement { app.buttons["chatfrom.close"] }

    private func waitUntilHittable(_ element: XCUIElement, _ hittable: Bool = true, timeout: TimeInterval = 4, file: StaticString = #filePath, line: UInt = #line) {
        let wanted = expectation(for: NSPredicate(format: "isHittable == %@", NSNumber(value: hittable)), evaluatedWith: element)
        let result = XCTWaiter.wait(for: [wanted], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element) is \(hittable ? "not " : "")hittable", file: file, line: line)
    }

    private func signIn() {
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Open from code"].waitForExistence(timeout: 5))
    }

    private func close() {
        closeButton.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5))
    }

    func testTheBubbleStaysOnTopWhenTheAppChangesItsRoot() {
        launch()
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        waitUntilHittable(bubble)
        sleep(1)
        shot("01-sign-in")

        signIn()
        sleep(1)
        shot("02-tabs")
        waitUntilHittable(bubble)
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertLessThan(bubble.frame.maxY, app.tabBars.firstMatch.frame.minY + 1, "the bubble is on the tab bar")
        }
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'loaded'")).firstMatch.waitForExistence(timeout: 5))
        close()
        waitUntilHittable(bubble)
    }

    func testAnInsetLiftsTheBubble() {
        launch()
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        let plain = bubble.frame.maxY
        app.terminate()
        launch(inset: 60)
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        XCTAssertEqual(plain - bubble.frame.maxY, 60, accuracy: 1)
    }

    func testTheAppCanMoveTheBubbleWhileItShows() {
        launch()
        signIn()
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        let plain = bubble.frame.maxY
        tapRow("Lift the bubble")
        // It glides there.
        sleep(1)
        XCTAssertEqual(plain - bubble.frame.maxY, 80, accuracy: 1)
        tapRow("Lower the bubble")
        sleep(1)
        XCTAssertEqual(bubble.frame.maxY, plain, accuracy: 1)
    }

    func testTheBubbleStepsAsideWhileTheKeyboardIsOverIt() {
        launch()
        signIn()
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        let note = app.textFields["note"]
        note.tap()
        // A new simulator's first keyboard shows a tip about sliding across the letters.
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 3), "the bubble shows through the keyboard")
        shot("keyboard-over-the-bubble")
        note.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(bubble.waitForExistence(timeout: 3), "the bubble did not come back once the keyboard went")
    }

    func testTheCellOpensTheChatWithItsOwnWords() {
        launch()
        signIn()
        let cell = app.buttons["chatfrom.button"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertEqual(cell.label, "Ask our assistant")
        sleep(1)
        shot("03-cell")
        cell.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        close()
    }

    func testTheAppOpensTheChatFromItsOwnCode() {
        launch()
        signIn()
        app.staticTexts["Open from code"].tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        close()
    }

    func testASheetOfTheAppsCoversTheBubbleAndTheChatOpensOverIt() {
        launch()
        signIn()
        waitUntilHittable(bubble)
        tapRow("Show a sheet")
        let done = app.buttons["Done with the sheet"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        sleep(1)
        shot("04-sheet-over-bubble")
        expectCovered(bubble)
        let row = app.buttons["chatfrom.button"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(web.waitForExistence(timeout: 5))
        sleep(1)
        shot("05-chat-over-sheet")
        close()
        waitUntilHittable(done)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        waitUntilHittable(bubble)
    }

    func testAFullScreenOfTheAppsCoversTheBubbleAndGivesItBack() {
        launch()
        signIn()
        waitUntilHittable(bubble)
        tapRow("Show a full screen")
        let done = app.buttons["Done with the sheet"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        // Longer than the bubble's look around, which must not bring it over the screen.
        sleep(2)
        shot("06-full-screen-over-bubble")
        expectCovered(bubble)
        // A row on that screen opens the chat over it, though the app's other screens have left the window.
        app.buttons["chatfrom.button"].firstMatch.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "the row on a full screen of the app's did not open the chat")
        close()
        waitUntilHittable(done)
        expectCovered(bubble)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        waitUntilHittable(bubble)
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
    }

    func testTheAppCanHideAndStopTheBubble() {
        launch()
        signIn()
        waitUntilHittable(bubble)
        tapRow("Hide the bubble")
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 3))
        tapRow("Show the bubble")
        XCTAssertTrue(bubble.waitForExistence(timeout: 3))
        waitUntilHittable(bubble)
        tapRow("Stop the bubble")
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 3))
        // The row still works.
        app.buttons["chatfrom.button"].tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
    }

    func testTheChatStaysUprightIfTheAppIs() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "this app turns on an iPad")
        launch()
        signIn()
        tapRow("Open from code")
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        sleep(2)
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.height, frame.width, "the chat turned when the app does not")
    }

    func testAChatAskedForWhileTheLastIsClosingOpensOnceItHasGone() {
        launch()
        signIn()
        tapRow("Close and at once open another")
        XCTAssertTrue(app.staticTexts["Lumen Ceramics"].waitForExistence(timeout: 5), "the first chatbot did not open")
        expectLog("path /mobile/second-bot", timeout: 12)
        XCTAssertTrue(app.staticTexts["Second Chatbot"].exists)
        close()
        waitUntilHittable(bubble)
    }

    func testASecondChatbotOpensOverTheFirstWithoutACrash() {
        launch()
        signIn()
        tapRow("Open two chatbots")
        XCTAssertTrue(app.staticTexts["Lumen Ceramics"].waitForExistence(timeout: 5), "the first chatbot did not open")
        // A moment later the app asks for the other chatbot with this one open: this one closes, and that one opens.
        expectLog("path /mobile/second-bot", timeout: 12)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.staticTexts["Second Chatbot"].exists)
        close()
        waitUntilHittable(bubble)
    }

    func testClosingThenOpeningTheSameChatbotInTheCompletionOpensIt() {
        launch()
        signIn()
        tapRow("Close then open again")
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        // After three seconds it closes, and opening it again as that finishes has to work. Well past that, it is open.
        sleep(6)
        XCTAssertTrue(closeButton.exists, "it did not open again")
        waitUntilHittable(closeButton)
        close()
    }

    func testClosingTheChatTakesWhatIsOnTopOfItToo() {
        launch()
        signIn()
        tapRow("Close with something on top")
        let done = app.buttons["Done with the sheet"]
        XCTAssertTrue(done.waitForExistence(timeout: 8), "nothing went on top")
        XCTAssertTrue(done.waitForNonExistence(timeout: 8), "what was on top stayed")
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3), "the chat stayed")
        waitUntilHittable(bubble)
    }

    func testAWindowThatGoesAwayWithTheChatOpenLeavesEverythingWorking() {
        launch()
        signIn()
        tapRow("Replace the window with the chat open")
        XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
        // The window goes after a moment, and the chat with it.
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 8))
        XCTAssertTrue(bubble.waitForExistence(timeout: 4), "the bubble never came back")
        waitUntilHittable(bubble)
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "the chat would not open again")
        expectLog("loaded")
    }

    func testTheBubbleDoesNotFollowOntoAnAppsLockScreen() {
        launch()
        signIn()
        waitUntilHittable(bubble)
        tapRow("Show a lock window")
        let unlock = app.buttons["Unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        sleep(2)
        shot("07-lock-window")
        XCTAssertFalse(bubble.isHittable, "the bubble is on the lock screen")
        unlock.tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 3))
        waitUntilHittable(bubble)
    }

    func testAClosedChatbotsRowIsGreyAndReadsAsNotEnabled() {
        launch(bot: "closed-bot")
        signIn()
        let cell = app.buttons["chatfrom.button"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        let disabled = expectation(for: NSPredicate(format: "isEnabled == false"), evaluatedWith: cell)
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 8), .completed, "a closed chatbot's row reads as enabled")
        XCTAssertFalse(bubble.exists)
    }

    func testHidingTheBubbleBeforeStartingItHolds() {
        launch(environment: ["CHATFROM_HIDE_FIRST": "1"])
        signIn()
        sleep(3)
        XCTAssertFalse(bubble.exists, "the bubble showed though the app had hidden it first")
        tapRow("Show the bubble")
        XCTAssertTrue(bubble.waitForExistence(timeout: 3))
    }

    func testTheAppsOwnWordsOnARow() {
        launch(environment: ["CHATFROM_GERMAN": "1"])
        signIn()
        tapRow("Show a sheet")
        let row = app.buttons["chatfrom.button"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let words = expectation(for: NSPredicate(format: "label == %@", "Mit Lumen Ceramics chatten"), evaluatedWith: row)
        XCTAssertEqual(XCTWaiter.wait(for: [words], timeout: 5), .completed, "the row says: \(row.label)")
    }

    func testAChatAskedForBeforeThereIsAWindowOpensWhenThereIsOne() {
        launch(openAtLaunch: true)
        XCTAssertTrue(closeButton.waitForExistence(timeout: 8), "the chat asked for at launch never opened")
        expectLog("loaded")
    }
}
