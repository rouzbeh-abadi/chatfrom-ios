import XCTest

// For ChatFrom's maintainers: the SDK with ChatFrom's real chat page, to run by
// hand. It needs a server that serves one. Skipped unless TEST_RUNNER_CHATFROM_REAL_BASE is set.
//
// With TEST_RUNNER_CHATFROM_REAL_TURNS set to the address of a stand-in that answers
// the chat and lists what it was sent, in front of a local copy of the ChatFrom web app
// (its repository has one), every test here can run, at no cost. Against chatfrom.io, set TEST_RUNNER_CHATFROM_REAL_BOT
// to a chatbot opened to mobile apps and run only testAQuestionAndItsAnswer: each
// answer uses that account's credits. It needs no stand-in, and waits 20 seconds for
// the answer instead of looking for particular words.

final class RealPageTests: XCTestCase {
    private var app: XCUIApplication!
    private let settings = ProcessInfo.processInfo.environment

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipIf(settings["CHATFROM_REAL_BASE"] == nil, "no server with the real page")
    }

    private var defaultBot: String { settings["CHATFROM_REAL_BOT"] ?? "real-remember" }

    private func launch(bot: String? = nil, arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment["CHATFROM_BASE_URL"] = settings["CHATFROM_REAL_BASE"]
        app.launchEnvironment["CHATFROM_BOT"] = bot ?? defaultBot
        app.launch()
    }

    private func shot(_ name: String) {
        guard let folder = settings["CHATFROM_SHOTS"] else { return }
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(folder)/real-\(device)-\(name).png"))
    }

    private var bubble: XCUIElement { app.buttons["chatfrom.bubble"] }
    private var closeButton: XCUIElement { app.buttons["chatfrom.close"] }
    private var newChat: XCUIElement { app.buttons["chatfrom.new"] }
    private var web: XCUIElement { app.webViews.firstMatch }

    private func says(_ text: String) -> XCUIElement {
        web.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func open() {
        XCTAssertTrue(bubble.waitForExistence(timeout: 40), "no bubble: is the page up?")
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
    }

    private func close() {
        closeButton.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 5))
    }

    private func goToAccount() {
        let tab = app.tabBars.buttons["Account"]
        (tab.exists ? tab : app.buttons["Account"].firstMatch).tap()
    }

    private func goToShop() {
        let tab = app.tabBars.buttons["Shop"]
        (tab.exists ? tab : app.buttons["Shop"].firstMatch).tap()
    }

    /// Sends a question and waits for the whole answer: the box is free again once it has finished.
    private func ask(_ question: String, file: StaticString = #filePath, line: UInt = #line) {
        let box = web.textFields.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 20), "no message box", file: file, line: line)
        box.tap()
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 1) { tip.tap() }
        box.typeText(question + "\n")
        XCTAssertTrue(says(question).waitForExistence(timeout: 10), "the question did not go", file: file, line: line)
        if settings["CHATFROM_REAL_TURNS"] != nil {
            XCTAssertTrue(says("delivery guide").waitForExistence(timeout: 20), "no answer came", file: file, line: line)
            sleep(1)
        } else {
            sleep(20)
        }
    }

    private struct Turn: Decodable {
        let channel: String
        let visitorId: String
        let sessionId: String
        let userToken: String?
        let message: String
    }

    private func turns() throws -> [Turn] {
        let address = try XCTUnwrap(settings["CHATFROM_REAL_TURNS"])
        let done = expectation(description: "turns")
        var received: Data?
        URLSession.shared.dataTask(with: URL(string: "\(address)/__turns")!) { data, _, _ in
            received = data
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 5)
        return try JSONDecoder().decode([Turn].self, from: XCTUnwrap(received))
    }

    private func requireStandIn() throws {
        try XCTSkipIf(settings["CHATFROM_REAL_TURNS"] == nil, "needs the stand-in that answers the chat")
    }

    /// Nothing kept from an earlier test: a sign-out with someone named clears this site's data.
    private func startClean() throws {
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 10))
        goToShop()
    }

    // MARK: The chat itself

    func testAQuestionAndItsAnswer() throws {
        launch()
        try startClean()
        XCTAssertTrue(bubble.waitForExistence(timeout: 40), "no bubble: is the chatbot open to mobile apps?")
        sleep(1)
        shot("01-bubble")
        open()
        sleep(2)
        shot("02-welcome")
        XCTAssertFalse(newChat.isHittable, "offers a new conversation with none going")
        ask("Do you ship to Norway?")
        sleep(1)
        shot("03-answered")
        let shown = NSPredicate(format: "isHittable == true")
        expectation(for: shown, evaluatedWith: newChat)
        waitForExpectations(timeout: 5)

        close()
        sleep(1)
        bubble.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(says("Do you ship to Norway?").exists, "closing the chat lost the conversation")

        newChat.tap()
        XCTAssertTrue(says("Do you ship to Norway?").waitForNonExistence(timeout: 5), "New conversation left the old one")
        let hidden = NSPredicate(format: "isHittable == false")
        expectation(for: hidden, evaluatedWith: newChat)
        waitForExpectations(timeout: 5)
        sleep(1)
        shot("04-new-conversation")
    }

    func testTheBoxAndTheNoticeStayAboveTheKeyboard() throws {
        launch()
        open()
        let box = web.textFields.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 20))
        box.tap()
        let tip = app.buttons["Continue"]
        if tip.waitForExistence(timeout: 1) { tip.tap() }
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        sleep(1)
        shot("05-keyboard")
        XCTAssertLessThanOrEqual(box.frame.maxY, keyboard.frame.minY, "the keyboard covers the message box")
        let notice = says("You're chatting with an AI assistant")
        XCTAssertTrue(notice.exists, "no notice that it is an AI")
        XCTAssertLessThanOrEqual(notice.frame.maxY, keyboard.frame.minY, "the keyboard covers the notice that it is an AI")
        XCTAssertTrue(closeButton.isHittable, "the header went off the screen")
        closeButton.tap()
        XCTAssertTrue(keyboard.waitForNonExistence(timeout: 3), "the keyboard stayed up after the chat closed")
    }

    func testTheChatFitsAtTheLargestTextItFollows() throws {
        launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        open()
        let box = web.textFields.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 20))
        sleep(1)
        shot("08-largest-text")
        ask("Do you ship to Norway?")
        shot("09-largest-text-answered")
        let window = app.windows.firstMatch.frame
        let question = says("Do you ship to Norway?")
        XCTAssertLessThanOrEqual(question.frame.maxX, window.maxX, "the words ran off the side")
        XCTAssertTrue(box.isHittable, "the message box cannot be reached")
    }

    func testThePaperclipOpensThePicker() throws {
        launch()
        open()
        let clip = web.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "attach")).firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout: 20), "no paperclip: \(web.buttons.allElementsBoundByIndex.map(\.label))")
        clip.tap()
        let choices = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@", "Photo Library", "Choose File")).firstMatch
        XCTAssertTrue(choices.waitForExistence(timeout: 5), "no picker came")
        sleep(1)
        shot("06-picker")
        XCTAssertTrue(closeButton.exists, "the chat went away when the picker opened")
    }

    func testPoweredByOpensOutsideTheApp() throws {
        launch()
        open()
        let link = web.links["ChatFrom"]
        XCTAssertTrue(link.waitForExistence(timeout: 20))
        link.tap()
        expectSafari()
    }

    func testALinkInAnAnswerOpensOutsideTheApp() throws {
        try requireStandIn()
        launch()
        open()
        ask("Where is the guide?")
        web.links.matching(NSPredicate(format: "label == %@", "delivery guide")).firstMatch.tap()
        expectSafari()
        app.activate()
        XCTAssertTrue(says("Where is the guide?").waitForExistence(timeout: 5), "the chat went somewhere else")
    }

    // MARK: What is kept, and for whom

    func testARememberedChatComesBackAfterALaunch() throws {
        try requireStandIn()
        launch()
        try startClean()
        open()
        ask("Remember this one")
        let visitor = try XCTUnwrap(turns().last?.visitorId)
        XCTAssertEqual(try turns().last?.channel, "app")
        // Give the store a moment: it writes after the answer.
        sleep(2)
        app.terminate()
        launch()
        open()
        XCTAssertTrue(says("Remember this one").waitForExistence(timeout: 20), "the chat was not kept")
        ask("And another")
        XCTAssertEqual(try turns().last?.visitorId, visitor, "a new visitor after a launch")
    }

    func testAChatTheOwnerDoesNotRememberIsGoneAfterALaunch() throws {
        try requireStandIn()
        launch(bot: "real-forget")
        open()
        ask("Keep this for the tab only")
        let visitor = try XCTUnwrap(turns().last?.visitorId)
        sleep(2)
        app.terminate()
        launch(bot: "real-forget")
        open()
        XCTAssertTrue(web.textFields.firstMatch.waitForExistence(timeout: 20))
        sleep(2)
        XCTAssertFalse(says("Keep this for the tab only").exists, "a chat the owner said not to keep came back")
        ask("A new one")
        XCTAssertNotEqual(try turns().last?.visitorId, visitor, "the same visitor after a launch, with Remember off")
    }

    func testAChatBegunBeforeSigningInCarriesOver() throws {
        try requireStandIn()
        launch()
        try startClean()
        open()
        ask("Before signing in")
        let visitor = try XCTUnwrap(turns().last?.visitorId)
        XCTAssertNil(try turns().last?.userToken)
        close()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        goToShop()
        open()
        XCTAssertTrue(says("Before signing in").waitForExistence(timeout: 5), "signing in lost the chat")
        ask("After signing in")
        let turn = try XCTUnwrap(turns().last)
        XCTAssertEqual(turn.visitorId, visitor, "signing in made a new visitor")
        XCTAssertEqual(turn.userToken, "token-sara")
    }

    func testARefreshedTokenKeepsTheChatAndGoesWithTheNextQuestion() throws {
        try requireStandIn()
        launch()
        try startClean()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        goToShop()
        open()
        ask("First with the token")
        XCTAssertEqual(try turns().last?.userToken, "token-sara")
        close()
        goToAccount()
        app.buttons["Refresh the token"].tap()
        goToShop()
        open()
        XCTAssertTrue(says("First with the token").waitForExistence(timeout: 5), "a token refresh lost the chat")
        ask("Second with the token")
        XCTAssertEqual(try turns().last?.userToken, "token-sara-2")
    }

    func testAnotherPersonStartsFromNothing() throws {
        try requireStandIn()
        launch()
        try startClean()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        goToShop()
        open()
        ask("Sara's private question")
        let sara = try XCTUnwrap(turns().last)
        close()
        goToAccount()
        // Nobody told the SDK she signed out: only that someone else is here.
        app.buttons["Sign in as Tom"].tap()
        goToShop()
        open()
        XCTAssertTrue(web.textFields.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertFalse(says("Sara's private question").exists, "Tom sees Sara's chat")
        shot("07-next-person")
        ask("Tom's question")
        let tom = try XCTUnwrap(turns().last)
        XCTAssertNotEqual(tom.visitorId, sara.visitorId, "Tom is the same visitor as Sara")
        XCTAssertNotEqual(tom.sessionId, sara.sessionId, "Tom goes on with Sara's conversation")
        XCTAssertEqual(tom.userToken, "token-tom")
    }

    func testAnotherPersonAtTheNextLaunchStartsFromNothing() throws {
        try requireStandIn()
        launch()
        try startClean()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        goToShop()
        open()
        ask("Sara's question before a restart")
        let sara = try XCTUnwrap(turns().last)
        sleep(2)
        app.terminate()
        // The page loads before the app says who is signed in, as an app that restores a session does.
        launch()
        goToAccount()
        app.buttons["Sign in as Tom"].tap()
        goToShop()
        open()
        XCTAssertTrue(web.textFields.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertFalse(says("Sara's question before a restart").exists, "Tom sees Sara's chat")
        ask("Tom after a restart")
        XCTAssertNotEqual(try turns().last?.visitorId, sara.visitorId)
    }

    func testSigningOutForgetsTheChatAndTheToken() throws {
        try requireStandIn()
        launch()
        try startClean()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        goToShop()
        open()
        ask("Before signing out")
        let sara = try XCTUnwrap(turns().last)
        close()
        goToAccount()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 2 times"].waitForExistence(timeout: 10))
        goToShop()
        open()
        XCTAssertTrue(web.textFields.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertFalse(says("Before signing out").exists, "the chat stayed after signing out")
        ask("Nobody signed in now")
        let next = try XCTUnwrap(turns().last)
        XCTAssertNotEqual(next.visitorId, sara.visitorId, "the same visitor after signing out")
        XCTAssertNil(next.userToken, "the token stayed after signing out")
        // And a chat begun now is kept by whoever signs in next.
        close()
        goToAccount()
        app.buttons["Sign in as Tom"].tap()
        goToShop()
        open()
        XCTAssertTrue(says("Nobody signed in now").waitForExistence(timeout: 5))
    }

    func testSigningOutAtTheNextLaunchLeavesNothingForTheNextOpen() throws {
        try requireStandIn()
        launch()
        try startClean()
        goToAccount()
        app.buttons["Sign in as Sara"].tap()
        goToShop()
        open()
        ask("Before the restart")
        sleep(2)
        app.terminate()
        // Her session ended while the app was closed, and the app says so as it starts.
        launch()
        goToAccount()
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.staticTexts["Signed out 1 time"].waitForExistence(timeout: 10))
        goToShop()
        open()
        XCTAssertTrue(web.textFields.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        XCTAssertFalse(says("Before the restart").exists, "the chat stayed after the session ended")
    }

    // MARK: A chatbot that is closed

    func testAClosedChatbotShowsNoBubbleAndWritesNothing() throws {
        launch(bot: settings["CHATFROM_REAL_CLOSED_BOT"] ?? "real-closed")
        goToAccount()
        let row = app.buttons["chatfrom.row"]
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        let disabled = NSPredicate(format: "isEnabled == false")
        expectation(for: disabled, evaluatedWith: row)
        waitForExpectations(timeout: 40)
        XCTAssertFalse(bubble.exists)
    }
}
