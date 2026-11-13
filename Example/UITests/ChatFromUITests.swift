import XCTest

// The SDK in a real app and a real web view, against Example/TestServer, which
// writes what it hears on the page. Start the server first:
//   node Example/TestServer/server.mjs
// A screenshot of each step goes to the folder in TEST_RUNNER_CHATFROM_SHOTS, if set.

/// That a link went to Safari. Safari is left running: this wait ends while it is still starting, and ending it then leaves the simulator unable to open anything, with the next launch waiting for ever.
func expectSafari(file: StaticString = #filePath, line: UInt = #line) {
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 10), "the link did not open outside the app", file: file, line: line)
}

final class ChatFromUITests: XCTestCase {
    private var app: XCUIApplication!
    private let server = "http://localhost:4599"

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(bot: String = "live-bot", bubble: Bool = true, base: String? = nil, maxAge: Int? = nil, gate: Bool = false, arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment["CHATFROM_BASE_URL"] = base ?? server
        app.launchEnvironment["CHATFROM_BOT"] = bot
        if !bubble { app.launchEnvironment["CHATFROM_NO_BUBBLE"] = "1" }
        if let maxAge { app.launchEnvironment["CHATFROM_MAX_AGE"] = String(maxAge) }
        if gate { app.launchEnvironment["CHATFROM_GATE"] = "1" }
        app.launch()
    }

    /// Asks the test server something, and gives back what it said.
    @discardableResult
    private func ask(_ path: String) throws -> String {
        let done = expectation(description: path)
        var answer: Data?
        URLSession.shared.dataTask(with: try XCTUnwrap(URL(string: server + path))) { data, _, _ in
            answer = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        return String(data: try XCTUnwrap(answer), encoding: .utf8) ?? ""
    }

    /// All a chatbot's pages have said, across documents, as the server heard it.
    private func reports(_ bot: String) throws -> [String] {
        try JSONDecoder().decode([String].self, from: Data(ask("/reports?id=\(bot)").utf8))
    }

    private func loads(_ bot: String) throws -> Int {
        Int(try ask("/loads?id=\(bot)")) ?? -1
    }

    private func shot(_ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["CHATFROM_SHOTS"] else { return }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/\(device)-\(name).png"))
    }

    private var bubble: XCUIElement { app.buttons["chatfrom.bubble"] }
    private var closeButton: XCUIElement { app.buttons["chatfrom.close"] }
    private var newChat: XCUIElement { app.buttons["chatfrom.new"] }
    private var retry: XCUIElement { app.buttons["chatfrom.retry"] }
    private var web: XCUIElement { app.webViews.firstMatch }

    private func lines(_ start: String) -> XCUIElementQuery {
        web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", start))
    }

    /// What the page wrote, once it has written it.
    private func expectLog(_ start: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(lines(start).firstMatch.waitForExistence(timeout: timeout), "the page never said: \(start)\nIt says: \(web.staticTexts.allElementsBoundByIndex.map(\.label))", file: file, line: line)
    }

    private func logs(_ start: String) -> Int {
        lines(start).count
    }

    /// Which load of this chatbot's page, by the server's count, is on screen.
    private func loadNumber(file: StaticString = #filePath, line: UInt = #line) -> Int {
        expectLog("load number", file: file, line: line)
        return Int(lines("load number").firstMatch.label.split(separator: " ").last ?? "") ?? -1
    }

    private func wait(until element: XCUIElement, isHittable hittable: Bool, timeout: TimeInterval = 4, file: StaticString = #filePath, line: UInt = #line) {
        let wanted = expectation(for: NSPredicate(format: "isHittable == %@", NSNumber(value: hittable)), evaluatedWith: element)
        XCTAssertEqual(XCTWaiter.wait(for: [wanted], timeout: timeout), .completed, "\(element) is \(hittable ? "not " : "")hittable", file: file, line: line)
    }

    private func openFromBubble() {
        XCTAssertTrue(bubble.waitForExistence(timeout: 15))
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
    }

    /// An iPad has its tabs at the top, and not as a tab bar a test can ask for.
    private func goToAccount() {
        let tab = app.tabBars.buttons["Account"]
        (tab.exists ? tab : app.buttons["Account"].firstMatch).tap()
    }

    /// With the bubble away, the row under Account opens the chat.
    private func openFromRow(file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons["chatfrom.row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        if !closeButton.waitForExistence(timeout: 5) {
            shot("open-failed")
            XCTFail("the row did not open the chat. The app shows: \(app.debugDescription)", file: file, line: line)
        }
    }

    private func close() {
        closeButton.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5))
    }

    /// Taps a button under Account that can be below the screen, since a form holds only the rows it shows, then goes back up to the row.
    private func tapLower(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[title]
        for _ in 0..<4 where !(button.exists && button.isHittable) { app.swipeUp() }
        XCTAssertTrue(button.isHittable, "no \(title) button", file: file, line: line)
        button.tap()
        for _ in 0..<4 where !(app.buttons["chatfrom.row"].exists && app.buttons["chatfrom.row"].isHittable) { app.swipeDown() }
    }

    /// Whoever an earlier test left signed in goes first, so a sign-out here starts from nobody.
    private func signOutWhoeverIsLeft() {
        app.buttons["Sign in as Sara"].tap()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 8))
    }

    // MARK: The bubble and the chat

    func testTheBubbleOpensTheChatAndComesBackWhenItCloses() {
        launch()
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        XCTAssertEqual(bubble.label, "Open chat with Lumen Ceramics")
        sleep(1)
        shot("01-bubble")
        // Above the tab bar, and not on it.
        let bar = app.tabBars.firstMatch
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertLessThan(bubble.frame.maxY, bar.frame.minY + 1, "the bubble is on the tab bar")
        }

        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        expectLog("loaded")
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 3), "the bubble stayed while the chat was open")
        sleep(1)
        shot("02-chat")

        let screen = app.windows.firstMatch.frame
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertLessThan(web.frame.width, screen.width - 100, "on an iPad the chat is a card")
            XCTAssertLessThan(web.frame.height, screen.height - 100, "on an iPad the chat is a card")
        } else {
            XCTAssertEqual(web.frame.width, screen.width, "on an iPhone the chat fills the screen")
            XCTAssertGreaterThan(web.frame.height, screen.height * 0.75, "on an iPhone the chat fills the screen")
            XCTAssertLessThanOrEqual(web.frame.maxY, screen.maxY, "the page stays inside the screen")
        }

        close()
        XCTAssertTrue(bubble.waitForExistence(timeout: 3))
        wait(until: bubble, isHittable: true)
    }

    func testTheWebViewStaysTheSamePageWhenTheChatClosesAndOpensAgain() {
        launch()
        openFromBubble()
        expectLog("loaded")
        web.buttons["Talk"].tap()
        expectLog("talking")
        close()
        sleep(3)
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        expectLog("talking")
        XCTAssertEqual(logs("loaded"), 1, "the page was loaded again")
    }

    func testAChatbotThatIsNotLiveShowsNoBubbleAndAGreyRow() {
        launch(bot: "closed-bot")
        goToAccount()
        let row = app.buttons["chatfrom.row"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let disabled = NSPredicate(format: "isEnabled == false")
        expectation(for: disabled, evaluatedWith: row)
        waitForExpectations(timeout: 8)
        XCTAssertFalse(bubble.exists)
        sleep(1)
        shot("03-closed-row")
    }

    func testAPillOnTheLeftFromTheOwnersSettings() {
        launch(bot: "left-bot")
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        XCTAssertEqual(bubble.label, "Ask us")
        XCTAssertLessThan(bubble.frame.midX, app.windows.firstMatch.frame.midX)
        XCTAssertGreaterThan(bubble.frame.width, bubble.frame.height, "words make it a pill")
        sleep(1)
        shot("04-pill-left")
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        sleep(1)
        shot("05-light-accent-header")
    }

    func testLeftAndRightAreTheOwnersInARightToLeftLanguage() {
        let rightToLeft = ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]
        launch(bot: "left-bot", arguments: rightToLeft)
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        XCTAssertLessThan(bubble.frame.midX, app.windows.firstMatch.frame.midX, "left is left")
        app.terminate()
        launch(bot: "live-bot", arguments: rightToLeft)
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(bubble.frame.midX, app.windows.firstMatch.frame.midX, "right is right")
    }

    func testTheAppCanHideTheBubble() {
        launch()
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        goToAccount()
        // On the switch itself, not the words beside it.
        app.switches["Show the bubble"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(bubble.waitForNonExistence(timeout: 3))
        openFromRow()
        close()
        XCTAssertFalse(bubble.exists, "closing the chat brought back a bubble the app hid")
    }

    func testTheBubbleRisesWhenATabBarComesLater() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "an iPad has its tabs at the top")
        launch(gate: true)
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        sleep(1)
        let low = bubble.frame.maxY
        app.buttons["Past the gate"].tap()
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertLessThan(bubble.frame.maxY, low, "the bubble did not move")
        XCTAssertLessThan(bubble.frame.maxY, bar.frame.minY + 1, "the bubble is on the tab bar")
    }

    func testTheRowOpensTheChatInSwiftUIAndInATable() {
        launch(bubble: false)
        goToAccount()
        sleep(1)
        shot("06-row")
        openFromRow()
        expectLog("loaded")
        close()
        app.buttons["In a UIKit table"].tap()
        let cell = app.buttons["chatfrom.button"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertEqual(cell.label, "Chat with Lumen Ceramics")
        sleep(1)
        shot("07-table-cell")
        cell.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertEqual(logs("loaded"), 1, "one web view for the app's run")
    }

    // MARK: The header

    func testNewConversationShowsWhileThereIsOneAndTellsThePage() {
        launch()
        openFromBubble()
        expectLog("loaded")
        XCTAssertFalse(newChat.isHittable)
        web.buttons["Talk"].tap()
        expectLog("talking")
        wait(until: newChat, isHittable: true, timeout: 3)
        sleep(1)
        shot("08-new-chat-button")
        newChat.tap()
        expectLog("heard new-chat")
    }

    func testPullingTheHeaderDownClosesTheChat() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "the system's sheet does this on an iPad")
        launch()
        openFromBubble()
        let top = app.staticTexts["Lumen Ceramics"]
        XCTAssertTrue(top.waitForExistence(timeout: 3))
        let start = top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5))
    }

    // MARK: The person

    func testThePageIsToldWhenThePersonChanges() {
        launch()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        openFromRow()
        // Loaded before she signed in, so the page was told by event.
        expectLog("heard token key=")
        expectLog("loaded key=none")
        XCTAssertEqual(logs("heard token"), 1)
        close()

        app.buttons["Refresh the token"].tap()
        openFromRow()
        XCTAssertEqual(logs("heard token"), 2)
        XCTAssertEqual(web.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "token=token-sara-2")).count, 1)
        close()
    }

    func testAReloadFindsThePersonBeforeThePageRunsAndNotOnceTheyHaveGone() {
        launch(maxAge: 3)
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        sleep(4)
        openFromRow()
        // Loaded again as it opened, so she is there from the start, and no event had to say so.
        expectLog("load number")
        XCTAssertEqual(web.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'loaded key=' AND label CONTAINS 'token=token-sara'")).count, 1, "\(web.staticTexts.allElementsBoundByIndex.map(\.label))")
        close()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 8))
        sleep(4)
        openFromRow()
        expectLog("load number")
        expectLog("loaded key=none token=none")
    }

    func testSignOutClearsStoredDataBeforeTheEventReachesThePage() {
        launch()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        openFromRow()
        expectLog("heard token")
        close()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 8))
        openFromRow()
        expectLog("heard sign-out mark=empty")
        sleep(1)
        shot("09-after-sign-out")
    }

    func testSignOutWithNobodyToForgetLeavesAChatBegunBeforeSigningIn() {
        launch()
        goToAccount()
        signOutWhoeverIsLeft()
        app.terminate()

        launch()
        goToAccount()
        openFromRow()
        expectLog("load number")
        close()
        // The page wrote its mark as it loaded. A sign-out that did anything would take it away.
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 8))
        openFromRow()
        XCTAssertEqual(logs("heard sign-out"), 0, "a sign-out with nobody signed in told the page")
        web.buttons["Show the mark"].tap()
        expectLog("mark now kept-")
    }

    func testASignOutTheAppDidNotLiveToFinishIsFinishedByTheNext() {
        launch()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        openFromRow()
        expectLog("heard token")
        close()
        app.buttons["Sign out and quit"].tap()
        XCTAssertEqual(app.wait(for: .notRunning, timeout: 5), true)

        launch()
        goToAccount()
        // As the README says, on a launch that finds nobody signed in.
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 8))
        openFromRow()
        web.buttons["Show the mark"].tap()
        expectLog("mark now")
        XCTAssertEqual(logs("mark now kept-"), 0, "Sara's data outlived her sign-out: \(web.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testTheNextPersonIsToldOnlyAfterTheSignOut() throws {
        launch()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        openFromRow()
        expectLog("heard token")
        close()
        // Both in the same moment, so only the SDK's own order keeps them apart.
        app.buttons["Switch to Tom"].tap()
        openFromRow()
        expectLog("heard sign-out")
        expectLog("heard token key=")
        sleep(1)
        let said = web.staticTexts.allElementsBoundByIndex.map(\.label).filter { $0.hasPrefix("heard") }
        let signedOutAt = try XCTUnwrap(said.firstIndex { $0.hasPrefix("heard sign-out") }, "\(said)")
        let tomAt = try XCTUnwrap(said.firstIndex { $0.contains("token-tom") }, "\(said)")
        XCTAssertLessThan(signedOutAt, tomAt, "\(said)")
        XCTAssertTrue(said[signedOutAt].hasSuffix("mark=empty"), "the event came before the removal: \(said)")
    }

    // MARK: Subscriptions

    func testOnlyAnAnonymousRevenueCatIdReachesThePageAndASignOutForgetsIt() {
        launch()
        goToAccount()
        signOutWhoeverIsLeft()
        tapLower("Use a RevenueCat id of the app's own")
        openFromRow()
        expectLog("purchases rc=none store=0")
        close()

        tapLower("Use an anonymous RevenueCat id")
        app.buttons["Sign in as Sara"].tap()
        openFromRow()
        expectLog("purchases rc=$RCAnonymousID:0123abcd")
        close()

        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 2 times"].waitForExistence(timeout: 8))
        openFromRow()
        expectLog("heard sign-out")
        web.buttons["Show the purchases"].tap()
        expectLog("purchases now rc=none store=0")
        close()

        // The next customer's, set after the sign-out, as the README says.
        tapLower("Use an anonymous RevenueCat id")
        openFromRow()
        web.buttons["Show the purchases"].tap()
        XCTAssertTrue(lines("purchases now rc=$RCAnonymousID:0123abcd").firstMatch.waitForExistence(timeout: 8), "\(web.staticTexts.allElementsBoundByIndex.map(\.label))")
    }

    func testASignOutReachesAPageAFailedReloadLeftRunning() throws {
        try ask("/reset?id=live-bot")
        launch(maxAge: 3)
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        openFromRow()
        // By event if the page was there already, or from the start if opening it loaded it again.
        XCTAssertTrue(web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "token=token-sara")).firstMatch.waitForExistence(timeout: 8))
        close()
        // The server starts failing. A stale open tries to reload, fails, and the old page is still running under the cover.
        try ask("/fail?id=live-bot&on=1")
        addTeardownBlock { [self] in try? ask("/fail?id=live-bot&on=0") }
        sleep(4)
        openFromRow()
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertFalse(web.staticTexts.firstMatch.exists, "VoiceOver can read the old page under the cover")
        close()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 8))
        // The old page heard it, though nobody could see it, and the reload after it failed too.
        sleep(1)
        let said = try reports("live-bot")
        let heard = said.filter { $0.contains("heard sign-out") }
        XCTAssertEqual(heard.count, 1, "\(said)")
        XCTAssertTrue(heard[0].hasSuffix("mark=empty"), "\(heard)")

        try ask("/fail?id=live-bot&on=0")
        openFromRow()
        if retry.waitForExistence(timeout: 2), retry.isHittable { retry.tap() }
        expectLog("loaded key=none token=none")
    }

    func testAPageOnItsWayOutCannotLiftTheCoverWhileItsReplacementLoads() throws {
        try ask("/reset?id=slow-ready-bot")
        launch(bot: "slow-ready-bot", bubble: false)
        goToAccount()
        // The first page takes five seconds to say it is ready. The sign-out comes before that, and starts a second load, which takes eight to arrive.
        app.buttons["Sign in as Sara"].tap()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 3))
        openFromRow()
        // So for a while now the old page has said ready, and its replacement has not arrived.
        let oldPageReady = NSPredicate { [self] _, _ in (try? reports("slow-ready-bot").contains { $0.hasSuffix("said ready") }) == true }
        expectation(for: oldPageReady, evaluatedWith: NSObject())
        waitForExpectations(timeout: 8)
        XCTAssertEqual(try loads("slow-ready-bot"), 2, "the second load should have begun")
        sleep(1)
        XCTAssertEqual(logs("said ready"), 0, "the cover came off over the page she signed out of")
        // And the new page arrives, with nobody on it.
        expectLog("load number 2", timeout: 15)
        expectLog("loaded key=none token=none")
    }

    // MARK: When it goes wrong

    func testAPageThatFailsOffersToTryAgain() {
        launch(bot: "broken-bot", bubble: false)
        goToAccount()
        openFromRow()
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        sleep(1)
        shot("10-failed")
        XCTAssertFalse(bubble.exists)
    }

    func testTryAgainWorksWhenThePageIsBack() throws {
        try ask("/reset?id=flaky-bot")
        try ask("/fail?id=flaky-bot&on=1")
        addTeardownBlock { [self] in try? ask("/fail?id=flaky-bot&on=0") }
        launch(bot: "flaky-bot", bubble: false)
        goToAccount()
        openFromRow()
        XCTAssertTrue(retry.waitForExistence(timeout: 8), "nothing offered to try again")
        try ask("/fail?id=flaky-bot&on=0")
        let before = try loads("flaky-bot")
        retry.tap()
        expectLog("load number \(before + 1)", timeout: 8)
        wait(until: retry, isHittable: false)
    }

    func testOpeningAChatThatFailedTriesAgainBeforeAnyoneAsks() throws {
        try ask("/reset?id=flaky-bot")
        try ask("/fail?id=flaky-bot&on=1")
        addTeardownBlock { [self] in try? ask("/fail?id=flaky-bot&on=0") }
        launch(bot: "flaky-bot", bubble: false)
        goToAccount()
        // The row's first load fails, with nobody looking.
        let failed = NSPredicate { [self] _, _ in ((try? loads("flaky-bot")) ?? 0) >= 1 }
        expectation(for: failed, evaluatedWith: NSObject())
        waitForExpectations(timeout: 8)
        sleep(1)
        try ask("/fail?id=flaky-bot&on=0")
        openFromRow()
        expectLog("load number 2", timeout: 8)
        XCTAssertFalse(retry.isHittable)
    }

    func testThePageSayingItFailedOffersToTryAgain() {
        launch(bot: "failing-bot", bubble: false)
        goToAccount()
        openFromRow()
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
    }

    func testAPageThatNeverSaysItIsReadyOffersToTryAgain() {
        launch(bot: "mute-bot", bubble: false)
        goToAccount()
        openFromRow()
        XCTAssertTrue(retry.waitForExistence(timeout: 25), "still waiting for a page that will never be ready")
    }

    func testNothingListeningOffersToTryAgain() {
        launch(bot: "live-bot", bubble: false, base: "http://localhost:4598")
        goToAccount()
        openFromRow()
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
    }

    func testThePageComesBackWhenTheSystemEndsItsProcessButNotWithoutLimit() throws {
        let udid = try XCTUnwrap(ProcessInfo.processInfo.environment["SIMULATOR_UDID"])
        try ask("/reset?id=live-bot")
        launch()
        openFromBubble()
        XCTAssertEqual(loadNumber(), 1)
        XCTAssertNotEqual(try ask("/end-page-process?udid=\(udid)"), "0", "no process to end")
        expectLog("load number 2", timeout: 15)
        XCTAssertNotEqual(try ask("/end-page-process?udid=\(udid)"), "0", "no process to end")
        expectLog("load number 3", timeout: 15)
        // The third in a minute: it stops, and offers to try again.
        XCTAssertNotEqual(try ask("/end-page-process?udid=\(udid)"), "0", "no process to end")
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        sleep(3)
        XCTAssertEqual(try loads("live-bot"), 3, "it went on loading a page that keeps dying")
    }

    // MARK: A page kept for the app's run

    func testAClosedChatKeepsRunningSoAnAnswerOnItsWayArrives() throws {
        launch()
        openFromBubble()
        expectLog("loaded")
        close()
        let closed = Date().timeIntervalSince1970 * 1000
        sleep(7)
        let reopened = Date().timeIntervalSince1970 * 1000
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        expectLog("tick")
        let times = lines("tick").allElementsBoundByIndex.compactMap { Double($0.label.split(separator: " ").last ?? "") }
        XCTAssertTrue(times.contains { $0 > closed && $0 < reopened }, "the page did nothing while the chat was closed: \(times), \(closed) to \(reopened)")
    }

    func testAPageOffScreenForLongIsLoadedAgainWhenTheChatOpens() {
        launch(maxAge: 4)
        openFromBubble()
        let first = loadNumber()
        close()
        sleep(5)
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        expectLog("load number \(first + 1)")
    }

    func testAPageOffScreenForLongIsLoadedAgainWhenTheAppComesBack() throws {
        try ask("/reset?id=live-bot")
        launch(maxAge: 4)
        openFromBubble()
        XCTAssertEqual(loadNumber(), 1)
        close()
        XCUIDevice.shared.press(.home)
        sleep(5)
        app.activate()
        // Only the app coming back, with nothing tapped.
        sleep(3)
        XCTAssertEqual(try loads("live-bot"), 2)
    }

    func testAPageJustSeenIsNotLoadedAgainWhenTheAppComesBack() {
        launch()
        openFromBubble()
        let first = loadNumber()
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 8))
        XCTAssertEqual(loadNumber(), first)
    }

    // MARK: Turning the device

    func testTheChatTurnsWithTheDeviceWhenTheAppDoes() {
        launch()
        openFromBubble()
        expectLog("loaded")
        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        sleep(2)
        shot("14-landscape")
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(window.width, window.height, "the chat did not turn")
        XCTAssertTrue(closeButton.isHittable, "the header went off the screen")
        XCTAssertLessThanOrEqual(web.frame.maxX, window.maxX)
        close()
        sleep(1)
        shot("15-landscape-bubble")
        XCTAssertTrue(bubble.isHittable)
    }

    // MARK: Links

    func testLinksLeaveTheAppAndTheWebViewStaysOnTheChat() {
        launch()
        openFromBubble()
        expectLog("path /mobile/live-bot")
        web.links["Outside"].tap()
        expectSafari()
        app.activate()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        expectLog("path /mobile/live-bot")
    }

    func testALinkToAnotherPageOfTheSiteDoesNotLoadInTheWebView() {
        launch()
        openFromBubble()
        expectLog("path /mobile/live-bot")
        web.links["Home"].tap()
        expectSafari()
        app.activate()
        expectLog("path /mobile/live-bot")
    }

    func testAPageCannotSendAnyoneOutOfTheAppWithTheChatClosed() throws {
        try ask("/reset?id=link-bot")
        launch(bot: "link-bot")
        // Three seconds after loading, the page clicks a link by itself, with the chat closed.
        XCTAssertTrue(bubble.waitForExistence(timeout: 8))
        sleep(5)
        XCTAssertTrue(try reports("link-bot").contains { $0.hasSuffix("clicking the link") }, "the page never tried")
        XCTAssertEqual(app.state, .runningForeground, "the page sent the person out of the app")
        XCTAssertNotEqual(XCUIApplication(bundleIdentifier: "com.apple.mobilesafari").state, .runningForeground)
    }

    // MARK: The keyboard

    func testTheBoxStaysAboveTheKeyboardWithNoBarOnIt() {
        launch()
        openFromBubble()
        let box = web.textFields["Message"]
        XCTAssertTrue(box.waitForExistence(timeout: 5))
        box.tap()
        // A new simulator's first keyboard shows a tip about sliding across the letters.
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 2) { tip.tap() }
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        sleep(1)
        shot("11-keyboard")
        XCTAssertLessThanOrEqual(box.frame.maxY, keyboard.frame.minY, "the keyboard covers the message box")
        XCTAssertTrue(closeButton.isHittable, "the header went off the screen")
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(app.buttons["Done"].exists, "the web view's bar of up, down and done is back")
        }
        box.typeText("Hello")
        sleep(1)
        shot("12-typed")
    }

    func testTheFilePickerOpensFromTheChat() {
        launch()
        openFromBubble()
        expectLog("loaded")
        web.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Attach")).firstMatch.tap()
        let choices = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", "Photo Library", "Choose File")).firstMatch
        XCTAssertTrue(choices.waitForExistence(timeout: 5), "no picker came")
        sleep(1)
        shot("13-file-picker")
        XCTAssertTrue(closeButton.exists, "the chat went away when the picker opened")
    }

    // MARK: Text size

    func testThePagesWordsGrowWithThePhonesTextSizeAndTheBoxStaysOnScreen() {
        launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"])
        openFromBubble()
        expectLog("path")
        sleep(1)
        shot("16-large-text")
        let large = lines("path").firstMatch.frame.height
        let window = app.windows.firstMatch.frame
        let box = web.textFields["Message"]
        XCTAssertTrue(box.exists)
        XCTAssertLessThanOrEqual(box.frame.maxY, window.maxY, "the message box went off the bottom")
        XCTAssertLessThanOrEqual(box.frame.maxX, window.maxX, "the message box went off the side")
        XCTAssertTrue(box.isHittable, "the message box cannot be reached")
        XCTAssertLessThanOrEqual(lines("path").firstMatch.frame.maxX, window.maxX, "the words ran off the side")
        app.terminate()
        launch()
        openFromBubble()
        expectLog("path")
        XCTAssertGreaterThan(large, lines("path").firstMatch.frame.height, "the page's words did not grow")
    }

    // MARK: Several windows

    func testAnotherWindowOnAnIPad() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "an iPhone has one window")
        launch()
        goToAccount()
        let another = app.buttons["Open another window"]
        XCTAssertTrue(another.waitForExistence(timeout: 5))
        another.tap()
        sleep(3)
        shot("17-another-window")
        // The first window has gone behind it, and the bubble has come to the one in front.
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        wait(until: bubble, isHittable: true)
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        expectLog("loaded")
        sleep(1)
        shot("18-chat-in-another-window")
        close()
        wait(until: bubble, isHittable: true)

        // A row in the window in front opens the chat there.
        let tabs = app.buttons.matching(identifier: "Account").allElementsBoundByIndex.filter(\.isHittable)
        try XCTUnwrap(tabs.first, "no tab in the window in front").tap()
        sleep(1)
        let rows = app.buttons.matching(identifier: "chatfrom.row").allElementsBoundByIndex.filter(\.isHittable)
        try XCTUnwrap(rows.first, "no row in the window in front").tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        close()
    }
}
